defmodule Typle.Inference do
  @moduledoc """
  Orchestrates type inference for a module or file.

  Parses the source file, expands macros in function bodies via
  `Typle.Inference.Expander` (powered by ExPanda), then walks each
  function definition through the expression inference engine.
  Collects a map of `{line, col} => Typle.Type.t()` for every
  expression in the module.
  """

  alias Typle.Inference.{Env, Expander, Expr, Guard, Pattern}
  alias Typle.Type

  require Logger

  @type type_map :: %{{non_neg_integer(), non_neg_integer()} => Type.t()}
  @type expr_map :: %{{non_neg_integer(), non_neg_integer()} => String.t()}
  @type skipped_form :: {non_neg_integer(), String.t()}
  @type inference_result :: %{
          types: type_map(),
          exprs: expr_map(),
          skipped: [skipped_form()]
        }

  @doc """
  Infers types for all expressions in the given source file.

  Returns `{:ok, %{types: type_map, exprs: expr_map}}` where `type_map` maps
  `{line, col}` to types and `expr_map` maps positions to source expression strings.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
  """
  @spec infer_file(String.t(), keyword()) :: {:ok, inference_result()} | {:error, term()}
  def infer_file(file_path, opts \\ []) do
    if opts[:unstable] do
      Typle.Unstable.types_for_file(file_path)
    else
      with {:ok, ast} <- Expander.expand_file(file_path) do
        module = extract_module_name(ast)
        env = Env.new(module: module, file: file_path)
        walk_file(ast, env)
      end
    end
  end

  # Walks the whole file, degrading to partial results rather than raising.
  #
  # Inference is best-effort by design: an AST shape the walker does not
  # understand should cost the user *that expression*, not the entire file.
  # Without this guard a single empty `case`/`cond` (whose clauses expand to
  # `{:__block__, _, []}` rather than a list) raised Protocol.UndefinedError
  # out of `Expr.infer/2` and took down every type query for the file.
  #
  # Top-level forms are walked one at a time and each result is folded into the
  # accumulator, so a form that raises only loses its own types -- everything
  # already inferred from earlier forms is still returned.
  defp walk_file(ast, env) do
    forms = top_level_forms(ast)

    # Two passes. The first infers every function's return type in an isolated
    # environment and records it, so that a call to a sibling defined *later* in
    # the file (`def a, do: b(x)` before `defp b`) resolves to a real type
    # instead of falling through to a compiled-beam lookup that cannot succeed
    # for a file that is not compiled yet. The second pass is the real walk,
    # which records positions and now sees those return types.
    env = Enum.reduce(forms, env, &declare_form/2)
    {env, skipped} = Enum.reduce(forms, {env, []}, &walk_form/2)

    {:ok,
     %{
       types: Env.all_types(env),
       exprs: Env.all_exprs(env),
       skipped: Enum.reverse(skipped)
     }}
  end

  # Infers one definition's return type in a throwaway environment and records
  # it. Types/exprs recorded during this probe are discarded -- the real walk
  # re-records them -- so only `fun_returns` survives.
  defp declare_form({kind, _meta, [head | _]} = form, env) when kind in [:def, :defp] do
    {name, args} = unwrap_head(head)

    if is_atom(name) and name != nil do
      {type, _probe_env} = walk_definition(form, env)
      Env.put_fun_return(env, name, length(args || []), type)
    else
      env
    end
  rescue
    _ -> env
  end

  defp declare_form(_form, env), do: env

  defp unwrap_head({:when, _, [head | _]}), do: unwrap_head(head)
  defp unwrap_head({name, _meta, args}), do: {name, args}
  defp unwrap_head(_), do: {nil, []}

  # Flattens `defmodule` and `__block__` wrappers into the list of top-level
  # forms, so each can be walked (and rescued) independently.
  defp top_level_forms({:defmodule, _meta, [_name, [do: body]]}), do: top_level_forms(body)
  defp top_level_forms({:__block__, _meta, exprs}), do: exprs
  defp top_level_forms(other), do: [other]

  defp walk_form(form, {acc_env, skipped}) do
    {_type, next_env} = walk_top_level(form, acc_env)
    {next_env, skipped}
  rescue
    e ->
      message = Exception.message(e)
      Logger.warning("Typle: skipping a top-level form in #{acc_env.file}: #{message}")

      # Report the skipped form so callers can surface it instead of silently
      # returning a smaller map than the user expects.
      {acc_env, [{form_line(form), message} | skipped]}
  end

  defp form_line({_kind, meta, _args}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp form_line(_form), do: 0

  @doc """
  Infers types for all expressions in a compiled module.

  Locates the source file from the module's compile info and delegates
  to `infer_file/1`.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
  """
  @spec infer_module(module(), keyword()) :: {:ok, inference_result()} | {:error, term()}
  def infer_module(module, opts \\ []) do
    if opts[:unstable] do
      Typle.Unstable.types_for(module)
    else
      case module.module_info(:compile)[:source] do
        nil -> {:error, {:no_source, module}}
        source -> infer_file(List.to_string(source))
      end
    end
  rescue
    _ -> {:error, {:module_not_available, module}}
  end

  # -- Private ---------------------------------------------------------------

  defp extract_module_name({:defmodule, _, [{:__aliases__, _, parts} | _]}) do
    Module.concat(parts)
  end

  defp extract_module_name({:__block__, _, exprs}) do
    Enum.find_value(exprs, fn
      {:defmodule, _, [{:__aliases__, _, parts} | _]} -> Module.concat(parts)
      _ -> nil
    end)
  end

  defp extract_module_name(_), do: nil

  defp walk_top_level({:defmodule, _meta, [_name, [do: body]]}, env) do
    walk_top_level(body, env)
  end

  defp walk_top_level({:__block__, _meta, exprs}, env) do
    Enum.reduce(exprs, {Type.none(), env}, fn expr, {_prev, acc_env} ->
      walk_top_level(expr, acc_env)
    end)
  end

  defp walk_top_level({kind, _meta, [_head | _rest]} = def_ast, env)
       when kind in [:def, :defp] do
    walk_definition(def_ast, env)
  end

  # Simple alias: alias Typle.Beam
  defp walk_top_level({:alias, _meta, [{:__aliases__, _, parts}]}, env)
       when length(parts) > 1 do
    short = List.last(parts)
    full = Module.concat(parts)
    {Type.dynamic(), Env.put_alias(env, short, full)}
  end

  # Alias with :as -- alias Typle.Beam, as: B
  defp walk_top_level(
         {:alias, _meta, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [short]}]]},
         env
       ) do
    full = Module.concat(parts)
    {Type.dynamic(), Env.put_alias(env, short, full)}
  end

  # Multi-alias: alias Typle.{Beam, Inference}
  defp walk_top_level(
         {:alias, _meta, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, suffixes}]},
         env
       ) do
    env =
      Enum.reduce(suffixes, env, fn {:__aliases__, _, suffix_parts}, acc ->
        short = List.last(suffix_parts)
        full = Module.concat(prefix ++ suffix_parts)
        Env.put_alias(acc, short, full)
      end)

    {Type.dynamic(), env}
  end

  defp walk_top_level(_other, env), do: {Type.dynamic(), env}

  defp walk_definition({_kind, _def_meta, [{:when, _, [head, guard]}, body_kw]}, env) do
    {fun_name, _meta, args} = head
    args = args || []

    # Infer argument types from patterns (start with dynamic)
    {bindings, env} =
      Enum.reduce(args, {%{}, env}, fn arg, {binds, acc_env} ->
        {new_binds, positions} = Pattern.infer(arg, Type.dynamic())
        {Map.merge(binds, new_binds), merge_positions(acc_env, positions)}
      end)

    # Refine with guard
    guard_refs = Guard.refine(guard)
    bindings = Map.merge(bindings, guard_refs)

    env = Env.push_scope(env, bindings)
    body = Keyword.get(body_kw, :do, nil)
    {type, env} = if body, do: Expr.infer(body, env), else: {Type.dynamic(), env}
    env = Env.pop_scope(env)
    {type, record_return(env, fun_name, args, type)}
  end

  defp walk_definition({_kind, _def_meta, [head, body_kw]}, env) do
    {fun_name, _meta, args} = head
    args = args || []

    {bindings, env} =
      Enum.reduce(args, {%{}, env}, fn arg, {binds, acc_env} ->
        {new_binds, positions} = Pattern.infer(arg, Type.dynamic())
        {Map.merge(binds, new_binds), merge_positions(acc_env, positions)}
      end)

    env = Env.push_scope(env, bindings)
    body = Keyword.get(body_kw, :do, nil)
    {type, env} = if body, do: Expr.infer(body, env), else: {Type.dynamic(), env}
    env = Env.pop_scope(env)
    {type, record_return(env, fun_name, args, type)}
  end

  defp walk_definition(_, env), do: {Type.dynamic(), env}

  # Remembers this function's return type so later calls to it -- including
  # calls to a sibling `defp` that has no compiled `.beam` yet -- resolve to a
  # real type instead of `dynamic()`.
  defp record_return(env, name, args, type) when is_atom(name) and name != nil do
    Env.put_fun_return(env, name, length(args), type)
  end

  defp record_return(env, _name, _args, _type), do: env

  defp merge_positions(env, positions) do
    Enum.reduce(positions, env, fn {{line, col}, {type, expr}}, acc ->
      Env.record_type(acc, line, col, type, expr)
    end)
  end
end
