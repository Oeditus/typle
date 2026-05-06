defmodule Typle do
  @moduledoc """
  Expression-level type query library for Elixir 1.20+.

  Reads inferred type signatures from compiled `.beam` files and performs
  best-effort type inference to answer "what type does the compiler think
  this expression has at line N, column C?"

  Before inference, all macros in function bodies are expanded via
  [ExPanda](https://hexdocs.pm/ex_panda), so pipe chains, `unless`,
  `use` directives, and library DSLs are resolved to their underlying
  forms. When expansion fails, the original AST is preserved and
  inference falls back to its existing best-effort handling.

  ## Usage

      # Point query
      Typle.type_at("lib/my_app/user.ex", 15, 5)
      #=> {:ok, %Typle.Type{kind: :binary}}

      # Full module map
      Typle.types_for(MyApp.User)
      #=> {:ok, %{{15, 5} => %Typle.Type{kind: :binary}, ...}}

      # Read function signatures from a compiled module
      Typle.signatures(Integer)
      #=> {:ok, [%{fun: :to_string, arity: 1, clauses: ...}, ...]}

  For deeper inference using compiler internals (opt-in, unstable),
  see `Typle.Unstable`.
  """

  alias Typle.{Beam, ExprMap, Inference, SignatureStore, Type, Unstable}

  @doc """
  Returns the inferred type at the given file position.

  Uses the stable inference engine (AST walking + signature store).

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
    * `:expr` - when `true` (default), returns a map with both the
      type and the source expression string:
      `{:ok, %{type: Type.t(), expr: String.t() | nil}}`.
      When `false`, returns `{:ok, Type.t()}` (legacy behaviour).
  """
  @spec type_at(String.t(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, Type.t() | %{type: Type.t(), expr: String.t() | nil}} | {:error, term()}
  def type_at(file, line, col, opts \\ []) do
    expr? = Keyword.get(opts, :expr, true)

    if opts[:unstable] do
      case Unstable.type_at(file, line, col) do
        {:ok, type} when expr? ->
          {:ok, %{type: type, expr: ExprMap.expr_at(file, line, col)}}

        other ->
          other
      end
    else
      with {:ok, %{types: types, exprs: exprs}} <- Inference.infer_file(file) do
        case Map.fetch(types, {line, col}) do
          {:ok, type} when expr? ->
            {:ok, %{type: type, expr: Map.get(exprs, {line, col})}}

          {:ok, type} ->
            {:ok, type}

          :error ->
            {:error, :no_type_at_position}
        end
      end
    end
  end

  @doc """
  Returns all inferred types for a module.

  Returns a map of `{line, col} => Typle.Type.t()` for each expression
  in the module's source file.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
    * `:expr` - when `true` (default), each value in the map becomes
      `%{type: Type.t(), expr: String.t() | nil}` instead of bare `Type.t()`.
  """
  @spec types_for(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def types_for(module, opts \\ []) do
    expr? = Keyword.get(opts, :expr, true)

    result =
      if opts[:unstable] do
        Unstable.types_for(module)
      else
        Inference.infer_module(module)
      end

    format_map_result(result, expr?, fn -> source_for_module(module) end)
  end

  @doc """
  Returns all inferred types for a source file.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
    * `:expr` - when `true` (default), each value in the map becomes
      `%{type: Type.t(), expr: String.t() | nil}` instead of bare `Type.t()`.
  """
  @spec types_for_file(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def types_for_file(file, opts \\ []) do
    expr? = Keyword.get(opts, :expr, true)

    result =
      if opts[:unstable] do
        Unstable.types_for_file(file)
      else
        Inference.infer_file(file)
      end

    format_map_result(result, expr?, fn -> file end)
  end

  @doc """
  Reads function signatures from a compiled module's `.beam` file.

  Returns the decoded type signatures as stored in the ExCk chunk.

  ## Options

    * `:unstable` - accepted for API consistency but currently
      has no effect (signatures are always read from BEAM chunks)
  """
  @spec signatures(module() | String.t(), keyword()) ::
          {:ok, [Beam.signature()]} | {:error, term()}
  def signatures(module_or_path, opts \\ []) do
    _ = opts
    Beam.read_signatures(module_or_path)
  end

  @doc """
  Looks up the return type of a function call.

  Queries the signature store for `module.function/arity` and returns
  the inferred return type.

  ## Options

    * `:unstable` - accepted for API consistency but currently
      has no effect (return types are always resolved via the signature store)
  """
  @spec return_type(module(), atom(), non_neg_integer(), keyword()) :: Type.t()
  def return_type(module, function, arity, opts \\ []) do
    _ = opts
    SignatureStore.return_type(module, function, arity, [])
  end

  # -- Private helpers -------------------------------------------------------

  # Formats an inference result for the map-returning public functions.
  # When the result already carries both maps (stable path), uses the
  # built-in expr_map. For the unstable path (bare type_map), falls back
  # to post-hoc extraction via ExprMap.
  defp format_map_result({:ok, %{types: types, exprs: exprs}}, true, _file_fn) do
    merged =
      Map.new(types, fn {pos, type} ->
        {pos, %{type: type, expr: Map.get(exprs, pos)}}
      end)

    {:ok, merged}
  end

  defp format_map_result({:ok, %{types: types}}, false, _file_fn) do
    {:ok, types}
  end

  # Unstable path returns a bare type_map (no %{types: ..., exprs: ...})
  defp format_map_result({:ok, type_map}, true, file_fn) when is_map(type_map) do
    file = file_fn.()
    fallback_exprs = if file, do: ExprMap.extract(file) |> unwrap_expr_map(), else: %{}

    merged =
      Map.new(type_map, fn {pos, type} ->
        {pos, %{type: type, expr: Map.get(fallback_exprs, pos)}}
      end)

    {:ok, merged}
  end

  defp format_map_result({:ok, type_map}, false, _file_fn) when is_map(type_map) do
    {:ok, type_map}
  end

  defp format_map_result(error, _expr?, _file_fn), do: error

  defp source_for_module(module) do
    try do
      case module.module_info(:compile)[:source] do
        nil -> nil
        source -> List.to_string(source)
      end
    rescue
      _ -> nil
    end
  end

  defp unwrap_expr_map({:ok, map}), do: map
  defp unwrap_expr_map(_), do: %{}
end
