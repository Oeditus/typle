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

  @type type_map :: %{{non_neg_integer(), non_neg_integer()} => Type.t()}
  @type expr_map :: %{{non_neg_integer(), non_neg_integer()} => String.t()}
  @type inference_result :: %{types: type_map(), exprs: expr_map()}

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
        {_type, env} = walk_top_level(ast, env)
        {:ok, %{types: Env.all_types(env), exprs: Env.all_exprs(env)}}
      end
    end
  end

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
    {_fun_name, _meta, args} = head
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
    {type, env}
  end

  defp walk_definition({_kind, _def_meta, [head, body_kw]}, env) do
    {_fun_name, _meta, args} = head
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
    {type, env}
  end

  defp walk_definition(_, env), do: {Type.dynamic(), env}

  defp merge_positions(env, positions) do
    Enum.reduce(positions, env, fn {{line, col}, {type, expr}}, acc ->
      Env.record_type(acc, line, col, type, expr)
    end)
  end
end
