defmodule Typle.Inference.Expr do
  @moduledoc """
  Walks AST expressions and infers their types.

  Each `infer/2` call takes an AST node and a type environment,
  returning `{type, updated_env}`.
  """

  alias Typle.Inference.{Builtins, Env, Guard, Pattern}
  alias Typle.SignatureStore
  alias Typle.Type

  @doc """
  Infers the type of an AST expression and records it in the environment.

  Returns `{inferred_type, updated_env}`.
  """
  @spec infer(Macro.t(), Env.t()) :: {Type.t(), Env.t()}

  # -- Literals --------------------------------------------------------------

  def infer(literal, env) when is_integer(literal), do: {Type.integer(), env}
  def infer(literal, env) when is_float(literal), do: {Type.float(), env}
  def infer(literal, env) when is_binary(literal), do: {Type.binary(), env}
  def infer(literal, env) when is_atom(literal), do: {Type.atom(literal), env}

  # -- Variables -------------------------------------------------------------

  def infer({var_name, meta, ctx}, env) when is_atom(var_name) and is_atom(ctx) do
    type = Env.get_var(env, var_name)
    env = maybe_record(env, meta, type, Atom.to_string(var_name))
    {type, env}
  end

  # -- Match operator: pattern = expr ----------------------------------------

  def infer({:=, meta, [pattern, expr]} = node, env) do
    {expr_type, env} = infer(expr, env)
    {bindings, positions} = Pattern.infer(pattern, expr_type)

    env = merge_positions(env, positions)

    env =
      Enum.reduce(bindings, env, fn {var, type}, acc ->
        Env.put_var(acc, var, type)
      end)

    env = maybe_record(env, meta, expr_type, Macro.to_string(node))
    {expr_type, env}
  end

  # -- Block: __block__ ------------------------------------------------------

  def infer({:__block__, _meta, exprs}, env) do
    Enum.reduce(exprs, {Type.none(), env}, fn expr, {_prev_type, acc_env} ->
      infer(expr, acc_env)
    end)
  end

  # -- Pipe operator: left |> right ------------------------------------------

  def infer({:|>, meta, [left, right]} = node, env) do
    {left_type, env} = infer(left, env)

    # Rewrite: left |> fun(args) => fun(left, args)
    {type, env} =
      case right do
        {fun, fun_meta, args} when is_list(args) ->
          infer({fun, fun_meta, [left | args]}, env)

        {fun, fun_meta, ctx} when is_atom(ctx) ->
          infer({fun, fun_meta, [left]}, env)

        _ ->
          {left_type, env}
      end

    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Remote call: Module.function(args) ------------------------------------

  def infer({{:., meta, [module, function]}, _call_meta, args} = node, env)
      when is_atom(module) and is_atom(function) do
    {arg_types, env} = infer_args(args, env)
    type = resolve_remote(module, function, length(args), arg_types)
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Remote call with aliased module: Alias.function(args) -----------------

  def infer({{:., meta, [{:__aliases__, _, parts}, function]}, _call_meta, args} = node, env)
      when is_atom(function) do
    {arg_types, env} = infer_args(args, env)
    module = Env.resolve_alias(env, parts)
    type = resolve_remote(module, function, length(args), arg_types)
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Map field access: map.field -------------------------------------------

  def infer({{:., meta, [expr, field]}, _call_meta, []} = node, env) when is_atom(field) do
    {_expr_type, env} = infer(expr, env)
    # Without precise map type tracking, we return dynamic
    type = Type.dynamic()
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Case expression -------------------------------------------------------

  def infer({:case, meta, [subject, [do: clauses]]} = node, env) do
    {subject_type, env} = infer(subject, env)

    {branch_types, branch_envs, env} =
      Enum.reduce(clauses, {[], [], env}, fn {:->, _clause_meta, [[pattern | guards], body]},
                                             {types, envs, acc_env} ->
        # Extract variable bindings from pattern
        {bindings, positions} = Pattern.infer(pattern, subject_type)
        acc_env = merge_positions(acc_env, positions)

        # Refine with guard types
        guard_refs =
          case guards do
            [] -> %{}
            [guard] -> Guard.refine(guard)
            _ -> %{}
          end

        merged_bindings = Map.merge(bindings, guard_refs)

        # Push scope, infer body, pop scope
        scoped_env = Env.push_scope(acc_env, merged_bindings)
        {body_type, scoped_env} = infer(body, scoped_env)

        # Collect the innermost scope's bindings for branch merging
        [scope | _] = scoped_env.scopes

        {[body_type | types], [scope | envs],
         %{acc_env | types: scoped_env.types, exprs: scoped_env.exprs}}
      end)

    result_type =
      case Enum.reverse(branch_types) do
        [single] -> single
        many -> Type.union(many)
      end

    env = Env.merge_branches(env, Enum.reverse(branch_envs))
    env = maybe_record(env, meta, result_type, Macro.to_string(node))
    {result_type, env}
  end

  # -- Cond expression -------------------------------------------------------

  def infer({:cond, meta, [[do: clauses]]} = node, env) do
    {branch_types, env} =
      Enum.reduce(clauses, {[], env}, fn {:->, _m, [[_condition], body]}, {types, acc_env} ->
        {body_type, acc_env} = infer(body, acc_env)
        {[body_type | types], acc_env}
      end)

    result_type = Type.union(Enum.reverse(branch_types))
    env = maybe_record(env, meta, result_type, Macro.to_string(node))
    {result_type, env}
  end

  # -- If/unless expression --------------------------------------------------

  def infer({if_or_unless, meta, [condition, branches]} = node, env)
      when if_or_unless in [:if, :unless] do
    {_cond_type, env} = infer(condition, env)

    do_branch = Keyword.get(branches, :do)
    else_branch = Keyword.get(branches, :else)

    {do_type, env} = if do_branch, do: infer(do_branch, env), else: {Type.atom(nil), env}
    {else_type, env} = if else_branch, do: infer(else_branch, env), else: {Type.atom(nil), env}

    result_type = Type.union([do_type, else_type])
    env = maybe_record(env, meta, result_type, Macro.to_string(node))
    {result_type, env}
  end

  # -- With expression -------------------------------------------------------

  def infer({:with, meta, clauses_and_body} = node, env) do
    # The body keywords ([do: ..., else: ...]) are normally the last element as
    # a keyword list, but a bare `{:do, body}` tuple also occurs -- e.g. after
    # macro expansion, or for a single-clause `with` written inline. Handle
    # both: anything else would leave a tuple in `clauses` and blow up when it
    # is enumerated.
    {clauses, body_kw} =
      case :lists.reverse(clauses_and_body) do
        [kw | rest] when is_list(kw) -> {:lists.reverse(rest), kw}
        [{key, _} = kw | rest] when key in [:do, :else] -> {:lists.reverse(rest), [kw]}
        _ -> {clauses_and_body, []}
      end

    env =
      Enum.reduce(clauses, env, fn
        {:<-, _m, [pattern, expr]}, acc_env ->
          {expr_type, acc_env} = infer(expr, acc_env)
          {bindings, positions} = Pattern.infer(pattern, expr_type)
          acc_env = merge_positions(acc_env, positions)
          Enum.reduce(bindings, acc_env, fn {var, type}, e -> Env.put_var(e, var, type) end)

        expr, acc_env ->
          {_type, acc_env} = infer(expr, acc_env)
          acc_env
      end)

    do_body = Keyword.get(body_kw, :do)
    else_body = Keyword.get(body_kw, :else)

    {do_type, env} = if do_body, do: infer(do_body, env), else: {Type.dynamic(), env}

    # The `else` block is part of the expression's value: a `with` that falls
    # through returns whatever `else` yields. Ignoring it under-reported types
    # at exactly the error paths a type query is most useful for.
    #
    # Note the body is a *list of `->` clauses*, not a single expression, so it
    # needs `infer_clauses/2` -- handing it to `infer/2` would match the generic
    # list clause and yield `list(dynamic())`.
    {else_type, env} = infer_clauses(else_body, env)

    result_type = Type.union([do_type, else_type])
    env = maybe_record(env, meta, result_type, Macro.to_string(node))
    {result_type, env}
  end

  # -- Fn (anonymous function) -----------------------------------------------

  def infer({:fn, meta, clauses} = node, env) do
    {clause_types, env} =
      Enum.map_reduce(clauses, env, fn {:->, _m, [params, body]}, acc_env ->
        {bindings, positions} =
          Enum.reduce(params, {%{}, acc_env}, fn param, {binds, e} ->
            {new_binds, pos} = Pattern.infer(param, Type.dynamic())
            {Map.merge(binds, new_binds), merge_positions(e, pos)}
          end)

        arg_types = Enum.map(params, fn param -> param_type(bindings, param) end)

        scoped_env = Env.push_scope(positions, bindings)
        {body_type, scoped_env} = infer(body, scoped_env)
        scoped_env = Env.pop_scope(scoped_env)

        # Carry the body's recorded types/exprs up, but drop the fn-local scope:
        # parameters must not leak into the enclosing environment.
        {{arg_types, body_type}, %{acc_env | types: scoped_env.types, exprs: scoped_env.exprs}}
      end)

    type = Type.function(clause_types)
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Try expression --------------------------------------------------------

  def infer({:try, meta, [blocks]} = node, env) do
    do_body = Keyword.get(blocks, :do)
    {do_type, env} = if do_body, do: infer(do_body, env), else: {Type.dynamic(), env}

    # `rescue`/`catch` bodies are also possible return values of the expression.
    {branch_types, env} =
      Enum.reduce([:rescue, :catch], {[do_type], env}, fn key, {types, acc_env} ->
        case Keyword.get(blocks, key) do
          nil ->
            {types, acc_env}

          body ->
            {type, acc_env} = infer_clauses(body, acc_env)
            {[type | types], acc_env}
        end
      end)

    result_type = Type.union(branch_types)
    env = maybe_record(env, meta, result_type, Macro.to_string(node))
    {result_type, env}
  end

  # -- Struct literal: %Mod{...} ---------------------------------------------

  def infer({:%, meta, [_struct, {:%{}, _, _pairs}]} = node, env) do
    type = Type.map()
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Map literal: %{...} --------------------------------------------------

  # A struct update `%{struct | key: value}` parses as
  #
  #     {:%{}, meta, [{:|, _, [struct, [key: value, ...]]}]}
  #
  # i.e. `pairs` holds a *single* `:|` tuple rather than `{key, value}` pairs.
  # This clause must precede the generic one below: that one destructures each
  # element as `{_key, val}`, so a `:|` tuple raises FunctionClauseError and
  # takes down inference for the whole file. Struct updates are ubiquitous in
  # real Elixir, so this is not an edge case.
  def infer({:%{}, meta, [{:|, _, [struct, updates]}]} = node, env) do
    # Infer the struct being updated so its sub-expressions are still recorded.
    {_struct_type, env} = infer(struct, env)

    # And each updated value; `updates` may be a keyword list or a map literal.
    env = infer_map_pairs(updates, env)

    type = Type.map()
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  def infer({:%{}, meta, pairs} = node, env) do
    env = infer_map_pairs(pairs, env)

    type = Type.map()
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Binary/string interpolation -------------------------------------------

  def infer({:<<>>, meta, _segments} = node, env) do
    type = Type.binary()
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Local call (unqualified): function(args) ------------------------------
  # Must come AFTER all specialized forms.

  def infer({function, meta, args} = node, env) when is_atom(function) and is_list(args) do
    {arg_types, env} = infer_args(args, env)
    arity = length(args)

    type =
      case Builtins.return_type(Kernel, function, arity, arg_types) do
        nil ->
          # A sibling `def`/`defp` in the file being analysed takes precedence:
          # its compiled `.beam` is usually absent or stale, so asking the
          # signature store would answer `dynamic()` for a function whose body
          # this very walk already inferred.
          case Env.get_fun_return(env, function, arity) do
            nil -> resolve_local(env, function, arity, arg_types)
            local_type -> local_type
          end

        builtin_type ->
          builtin_type
      end

    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  # -- Tuple literal: {a, b} or {a, b, c, ...} ------------------------------

  def infer({:{}, meta, elements} = node, env) do
    {elem_types, env} = infer_args(elements, env)
    type = Type.tuple(elem_types)
    env = maybe_record(env, meta, type, Macro.to_string(node))
    {type, env}
  end

  def infer({left, right}, env) do
    {left_type, env} = infer(left, env)
    {right_type, env} = infer(right, env)
    {Type.tuple([left_type, right_type]), env}
  end

  # -- List literal ----------------------------------------------------------

  def infer(elements, env) when is_list(elements) do
    case elements do
      [] ->
        {Type.empty_list(), env}

      _ ->
        {elem_types, env} = infer_args(elements, env)
        elem_type = Type.union(elem_types)
        {Type.list(elem_type), env}
    end
  end

  # -- Fallback: unknown expression ------------------------------------------

  def infer(_other, env), do: {Type.dynamic(), env}

  # -- Helpers ---------------------------------------------------------------

  # Infers the value of a *clause list* -- the shape `with ... else`, `try ...
  # rescue`, and `try ... catch` bodies take. Each clause is `{:->, meta,
  # [patterns, body]}`; the clause list's type is the union of every body type.
  #
  # This must not be folded into `infer/2`: a bare list there means a list
  # *literal*, so routing a clause list through it produced `list(dynamic())`
  # and silently discarded every branch type.
  defp infer_clauses(nil, env), do: {Type.none(), env}

  defp infer_clauses(clauses, env) when is_list(clauses) do
    if Enum.all?(clauses, &match?({:->, _, _}, &1)) do
      {types, env} =
        Enum.map_reduce(clauses, env, fn {:->, _meta, [patterns, body]}, acc_env ->
          # Bind any variables the clause head introduces, in their own scope.
          {bindings, acc_env} =
            Enum.reduce(patterns, {%{}, acc_env}, fn pattern, {binds, e} ->
              {new_binds, positions} = Pattern.infer(pattern, Type.dynamic())
              {Map.merge(binds, new_binds), merge_positions(e, positions)}
            end)

          scoped_env = Env.push_scope(acc_env, bindings)
          {body_type, scoped_env} = infer(body, scoped_env)
          scoped_env = Env.pop_scope(scoped_env)

          {body_type, %{acc_env | types: scoped_env.types, exprs: scoped_env.exprs}}
        end)

      {Type.union(types), env}
    else
      infer(clauses, env)
    end
  end

  defp infer_clauses(other, env), do: infer(other, env)

  # Resolves one `fn` parameter's type from the bindings the pattern produced.
  # Wildcards and non-variable patterns contribute `dynamic()`.
  defp param_type(bindings, {var_name, _meta, ctx})
       when is_atom(var_name) and is_atom(ctx) do
    Map.get(bindings, var_name, Type.dynamic())
  end

  defp param_type(_bindings, _param), do: Type.dynamic()

  # Falls back to the compiled module's signatures, or `dynamic()` when the
  # module is unknown (e.g. analysing a file that is not compiled yet).
  defp resolve_local(env, function, arity, arg_types) do
    case env.module do
      nil -> Type.dynamic()
      mod -> SignatureStore.return_type(mod, function, arity, arg_types)
    end
  end

  # Walks map/keyword pairs, inferring each value. Tolerates shapes that are
  # not `{key, value}` tuples (the `:|` struct-update form has its own clause
  # above, but this keeps the walk total rather than raising on anything
  # unexpected).
  defp infer_map_pairs(pairs, env) when is_list(pairs) do
    Enum.reduce(pairs, env, fn
      # Struct update: `%{struct | key: value}` parses as
      # `{:%{}, _, [{:|, _, [struct, pairs]}]}`, so the single "pair" is a bare
      # `:|` tuple rather than a `{key, value}` pair. Infer the struct being
      # updated and then its new values; without this the tuple fell through to
      # `infer(other, env)`, which has no clause for a bare `:|` atom and raised
      # FunctionClauseError on every struct update in the file.
      {:|, _meta, [struct, updates]}, acc ->
        {_type, acc} = infer(struct, acc)
        infer_map_pairs(updates, acc)

      {_key, val}, acc ->
        {_type, acc} = infer(val, acc)
        acc

      other, acc ->
        {_type, acc} = infer(other, acc)
        acc
    end)
  end

  defp infer_map_pairs(other, env) do
    {_type, env} = infer(other, env)
    env
  end

  defp infer_args(args, env) do
    Enum.map_reduce(args, env, fn arg, acc -> infer(arg, acc) end)
  end

  defp resolve_remote(module, function, arity, arg_types) do
    case Builtins.return_type(module, function, arity, arg_types) do
      nil -> SignatureStore.return_type(module, function, arity, arg_types)
      builtin_type -> builtin_type
    end
  end

  defp maybe_record(env, meta, type, expr) do
    line = Keyword.get(meta, :line, 0)
    col = Keyword.get(meta, :column, 0)

    if line > 0 do
      Env.record_type(env, line, col, type, expr)
    else
      env
    end
  end

  defp merge_positions(env, positions) do
    Enum.reduce(positions, env, fn {{line, col}, {type, expr}}, acc ->
      Env.record_type(acc, line, col, type, expr)
    end)
  end
end
