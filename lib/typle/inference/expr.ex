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
    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Match operator: pattern = expr ----------------------------------------

  def infer({:=, meta, [pattern, expr]}, env) do
    {expr_type, env} = infer(expr, env)
    bindings = Pattern.infer(pattern, expr_type)

    env =
      Enum.reduce(bindings, env, fn {var, type}, acc ->
        Env.put_var(acc, var, type)
      end)

    env = maybe_record(env, meta, expr_type)
    {expr_type, env}
  end

  # -- Block: __block__ ------------------------------------------------------

  def infer({:__block__, _meta, exprs}, env) do
    Enum.reduce(exprs, {Type.none(), env}, fn expr, {_prev_type, acc_env} ->
      infer(expr, acc_env)
    end)
  end

  # -- Pipe operator: left |> right ------------------------------------------

  def infer({:|>, meta, [left, right]}, env) do
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

    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Remote call: Module.function(args) ------------------------------------

  def infer({{:., meta, [module, function]}, _call_meta, args}, env)
      when is_atom(module) and is_atom(function) do
    {arg_types, env} = infer_args(args, env)
    arity = length(args)

    # Try builtins first, then signature store
    type =
      case Builtins.return_type(module, function, arity, arg_types) do
        nil -> SignatureStore.return_type(module, function, arity, arg_types)
        builtin_type -> builtin_type
      end

    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Map field access: map.field -------------------------------------------

  def infer({{:., meta, [expr, field]}, _call_meta, []}, env) when is_atom(field) do
    {_expr_type, env} = infer(expr, env)
    # Without precise map type tracking, we return dynamic
    type = Type.dynamic()
    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Case expression -------------------------------------------------------

  def infer({:case, meta, [subject, [do: clauses]]}, env) do
    {subject_type, env} = infer(subject, env)

    {branch_types, branch_envs, env} =
      Enum.reduce(clauses, {[], [], env}, fn {:->, _clause_meta, [[pattern | guards], body]},
                                             {types, envs, acc_env} ->
        # Extract variable bindings from pattern
        bindings = Pattern.infer(pattern, subject_type)

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

        {[body_type | types], [scope | envs], %{acc_env | types: scoped_env.types}}
      end)

    result_type =
      case Enum.reverse(branch_types) do
        [single] -> single
        many -> Type.union(many)
      end

    env = Env.merge_branches(env, Enum.reverse(branch_envs))
    env = maybe_record(env, meta, result_type)
    {result_type, env}
  end

  # -- Cond expression -------------------------------------------------------

  def infer({:cond, meta, [[do: clauses]]}, env) do
    {branch_types, env} =
      Enum.reduce(clauses, {[], env}, fn {:->, _m, [[_condition], body]}, {types, acc_env} ->
        {body_type, acc_env} = infer(body, acc_env)
        {[body_type | types], acc_env}
      end)

    result_type = Type.union(Enum.reverse(branch_types))
    env = maybe_record(env, meta, result_type)
    {result_type, env}
  end

  # -- If/unless expression --------------------------------------------------

  def infer({if_or_unless, meta, [condition, branches]}, env)
      when if_or_unless in [:if, :unless] do
    {_cond_type, env} = infer(condition, env)

    do_branch = Keyword.get(branches, :do)
    else_branch = Keyword.get(branches, :else)

    {do_type, env} = if do_branch, do: infer(do_branch, env), else: {Type.atom(nil), env}
    {else_type, env} = if else_branch, do: infer(else_branch, env), else: {Type.atom(nil), env}

    result_type = Type.union([do_type, else_type])
    env = maybe_record(env, meta, result_type)
    {result_type, env}
  end

  # -- With expression -------------------------------------------------------

  def infer({:with, meta, clauses_and_body}, env) do
    {body_kw, clauses} = Enum.split_with(clauses_and_body, &(is_tuple(&1) and elem(&1, 0) == :do))

    env =
      Enum.reduce(clauses, env, fn
        {:<-, _m, [pattern, expr]}, acc_env ->
          {expr_type, acc_env} = infer(expr, acc_env)
          bindings = Pattern.infer(pattern, expr_type)
          Enum.reduce(bindings, acc_env, fn {var, type}, e -> Env.put_var(e, var, type) end)

        expr, acc_env ->
          {_type, acc_env} = infer(expr, acc_env)
          acc_env
      end)

    do_body =
      case body_kw do
        [do: body] -> body
        [{:do, body} | _] -> body
        _ -> nil
      end

    {result_type, env} = if do_body, do: infer(do_body, env), else: {Type.dynamic(), env}
    env = maybe_record(env, meta, result_type)
    {result_type, env}
  end

  # -- Fn (anonymous function) -----------------------------------------------

  def infer({:fn, meta, _clauses}, env) do
    env = maybe_record(env, meta, %Type{kind: :function, params: []})
    {%Type{kind: :function, params: []}, env}
  end

  # -- Try expression --------------------------------------------------------

  def infer({:try, meta, [blocks]}, env) do
    do_body = Keyword.get(blocks, :do)
    {do_type, env} = if do_body, do: infer(do_body, env), else: {Type.dynamic(), env}
    env = maybe_record(env, meta, do_type)
    {do_type, env}
  end

  # -- Struct literal: %Mod{...} ---------------------------------------------

  def infer({:%, meta, [_struct, {:%{}, _, _pairs}]}, env) do
    type = Type.map()
    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Map literal: %{...} --------------------------------------------------

  def infer({:%{}, meta, pairs}, env) do
    env =
      Enum.reduce(pairs, env, fn {_key, val}, acc ->
        {_type, acc} = infer(val, acc)
        acc
      end)

    type = Type.map()
    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Binary/string interpolation -------------------------------------------

  def infer({:<<>>, meta, _segments}, env) do
    type = Type.binary()
    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Local call (unqualified): function(args) ------------------------------
  # Must come AFTER all specialized forms.

  def infer({function, meta, args}, env) when is_atom(function) and is_list(args) do
    {arg_types, env} = infer_args(args, env)
    arity = length(args)

    type =
      case Builtins.return_type(Kernel, function, arity, arg_types) do
        nil ->
          case env.module do
            nil -> Type.dynamic()
            mod -> SignatureStore.return_type(mod, function, arity, arg_types)
          end

        builtin_type ->
          builtin_type
      end

    env = maybe_record(env, meta, type)
    {type, env}
  end

  # -- Tuple literal: {a, b} or {a, b, c, ...} ------------------------------

  def infer({:{}, meta, elements}, env) do
    {elem_types, env} = infer_args(elements, env)
    type = Type.tuple(elem_types)
    env = maybe_record(env, meta, type)
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

  defp infer_args(args, env) do
    Enum.map_reduce(args, env, fn arg, acc -> infer(arg, acc) end)
  end

  defp maybe_record(env, meta, type) do
    line = Keyword.get(meta, :line, 0)
    col = Keyword.get(meta, :column, 0)

    if line > 0 do
      Env.record_type(env, line, col, type)
    else
      env
    end
  end
end
