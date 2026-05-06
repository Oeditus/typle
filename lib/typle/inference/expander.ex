defmodule Typle.Inference.Expander do
  @moduledoc """
  Macro expansion layer for the inference engine.

  Wraps `ExPanda` to produce fully-expanded ASTs before type inference.
  Expansion is applied at the function-body level (not whole-module),
  because the compiler's internal expander requires full compiler state
  for `defmodule` forms.

  When expansion fails for a body (e.g. a macro's defining module is not
  loaded), the original unexpanded AST is returned so the inference engine
  can fall back to its existing best-effort handling.
  """

  require Logger

  @doc """
  Parses a source file and expands macros in all function bodies.

  The module structure (`defmodule`, `def`/`defp`, `alias`, etc.) is
  preserved as-is. Only the `:do` bodies of function definitions are
  expanded via ExPanda.

  Returns `{:ok, expanded_ast}` on success, or `{:error, reason}` if
  parsing fails.
  """
  @spec expand_file(String.t(), keyword()) :: {:ok, Macro.t()} | {:error, term()}
  def expand_file(file_path, _opts \\ []) do
    with {:ok, source} <- File.read(file_path),
         {:ok, ast} <- parse(source, file_path) do
      {:ok, expand_bodies(ast)}
    end
  end

  @doc """
  Expands macros in an expression-level AST node.

  On expansion failure, logs a debug message and returns the original
  AST unchanged.
  """
  @spec expand_expr(Macro.t()) :: Macro.t()
  def expand_expr(ast) do
    quiet_expand(ast)
  rescue
    e ->
      Logger.debug("ExPanda expansion raised: #{inspect(e)}, using unexpanded AST")
      ast
  end

  # Runs ExPanda.expand/1 with :standard_error redirected to a disposable
  # StringIO so that :elixir_expand's "undefined variable" diagnostics
  # (written directly to :standard_error) don't leak to the user's terminal.
  defp quiet_expand(ast) do
    {:ok, sink} = StringIO.open("")
    original = Process.whereis(:standard_error)
    Process.unregister(:standard_error)
    Process.register(sink, :standard_error)

    try do
      case ExPanda.expand(ast) do
        {:ok, expanded} ->
          strip_unexpanded_markers(expanded)

        {:error, reason} ->
          Logger.debug("ExPanda expansion failed: #{inspect(reason)}, using unexpanded AST")
          ast
      end
    after
      Process.unregister(:standard_error)
      Process.register(original, :standard_error)
      StringIO.close(sink)
    end
  end

  @doc false
  @spec strip_unexpanded_markers(Macro.t()) :: Macro.t()
  def strip_unexpanded_markers(ast) do
    Macro.prewalk(ast, fn
      # ExPanda wraps unexpandable macros as:
      #   {:__block__, [], [{:@, [], [{:unexpanded, [], [_msg]}]}, original_node]}
      # Extract the original node so inference can attempt its best-effort handling.
      {:__block__, _meta, [{:@, _, [{:unexpanded, _, _}]}, original_node]} ->
        original_node

      other ->
        other
    end)
  end

  # -- Private ---------------------------------------------------------------

  defp parse(source, file) do
    Code.string_to_quoted(source,
      file: file,
      columns: true,
      token_metadata: true,
      unescape: false
    )
  end

  # Walk the module AST and expand only function bodies.

  defp expand_bodies({:defmodule, meta, [name, [do: body]]}) do
    {:defmodule, meta, [name, [do: expand_bodies(body)]]}
  end

  defp expand_bodies({:__block__, meta, exprs}) do
    {:__block__, meta, Enum.map(exprs, &expand_bodies/1)}
  end

  defp expand_bodies({kind, meta, [head, body_kw]}) when kind in [:def, :defp] do
    expanded_kw =
      Keyword.update(body_kw, :do, nil, fn
        nil -> nil
        body -> expand_expr(body)
      end)

    {kind, meta, [head, expanded_kw]}
  end

  defp expand_bodies(other), do: other
end
