defmodule Typle.Inference do
  @moduledoc """
  Orchestrates type inference for a module or file.

  Parses the source file, walks each function definition through the
  expression inference engine, and collects a map of
  `{line, col} => Typle.Type.t()` for every expression in the module.
  """

  alias Typle.Type
  alias Typle.Inference.{Env, Expr, Pattern, Guard}

  @type type_map :: %{{non_neg_integer(), non_neg_integer()} => Type.t()}

  @doc """
  Infers types for all expressions in the given source file.

  Returns a map of `{line, col} => type` for each expression node
  that has position metadata.
  """
  @spec infer_file(String.t()) :: {:ok, type_map()} | {:error, term()}
  def infer_file(file_path) do
    with {:ok, source} <- File.read(file_path),
         {:ok, ast} <- parse_with_metadata(source, file_path) do
      module = extract_module_name(ast)
      env = Env.new(module: module, file: file_path)
      {_type, env} = walk_top_level(ast, env)
      {:ok, Env.all_types(env)}
    end
  end

  @doc """
  Infers types for all expressions in a compiled module.

  Locates the source file from the module's compile info and delegates
  to `infer_file/1`.
  """
  @spec infer_module(module()) :: {:ok, type_map()} | {:error, term()}
  def infer_module(module) do
    case module.module_info(:compile)[:source] do
      nil -> {:error, {:no_source, module}}
      source -> infer_file(List.to_string(source))
    end
  rescue
    _ -> {:error, {:module_not_available, module}}
  end

  # -- Private ---------------------------------------------------------------

  defp parse_with_metadata(source, file) do
    Code.string_to_quoted(source,
      file: file,
      columns: true,
      token_metadata: true,
      unescape: false
    )
  end

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

  defp walk_top_level(_other, env), do: {Type.dynamic(), env}

  defp walk_definition({_kind, _def_meta, [{:when, _, [head, guard]}, body_kw]}, env) do
    {_fun_name, _meta, args} = head
    args = args || []

    # Infer argument types from patterns (start with dynamic)
    bindings =
      Enum.reduce(args, %{}, fn arg, acc ->
        Map.merge(acc, Pattern.infer(arg, Type.dynamic()))
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

    bindings =
      Enum.reduce(args, %{}, fn arg, acc ->
        Map.merge(acc, Pattern.infer(arg, Type.dynamic()))
      end)

    env = Env.push_scope(env, bindings)
    body = Keyword.get(body_kw, :do, nil)
    {type, env} = if body, do: Expr.infer(body, env), else: {Type.dynamic(), env}
    env = Env.pop_scope(env)
    {type, env}
  end

  defp walk_definition(_, env), do: {Type.dynamic(), env}
end
