defmodule Typle.Inference.Expander do
  @expand_timeout_ms 5_000

  @moduledoc """
  Macro expansion layer for the inference engine.

  Wraps `ExPanda` to produce fully-expanded ASTs before type inference.
  Expansion is applied at the function-definition level (the full `def`/`defp`
  form, not just the body), so that ExPanda's Walker registers function
  parameters as variables before expanding the body. The outer `defmodule`
  structure is preserved as-is because the compiler's internal expander
  requires full compiler state for module forms.

  Each expansion is guarded by a timeout (default #{@expand_timeout_ms}ms)
  to prevent hangs when `:elixir_expand` enters an infinite loop on
  certain AST patterns.
  """

  require Logger

  @doc """
  Parses a source file and expands macros in all function definitions.

  The module structure (`defmodule`, `alias`, etc.) is preserved as-is.
  Each `def`/`defp` form is expanded via ExPanda (including parameter
  registration) with a per-definition timeout guard.

  Returns `{:ok, expanded_ast}` on success, or `{:error, reason}` if
  parsing fails.
  """
  @spec expand_file(String.t(), keyword()) :: {:ok, Macro.t()} | {:error, term()}
  def expand_file(file_path, _opts \\ []) do
    with {:ok, source} <- File.read(file_path),
         {:ok, ast} <- parse(source, file_path) do
      {:ok, with_quiet_stderr(fn -> expand_defs(ast) end)}
    end
  end

  @doc """
  Expands macros in a full `def`/`defp` AST node (or expression).

  Uses `ExPanda.expand/1` with a timeout guard. On failure or timeout,
  returns the original AST unchanged.
  """
  @spec expand_node(Macro.t()) :: Macro.t()
  def expand_node(ast) do
    task = Task.async(fn -> ExPanda.expand(ast) end)

    case Task.yield(task, @expand_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, expanded}} ->
        strip_unexpanded_markers(expanded)

      {:ok, {:error, reason}} ->
        Logger.debug("ExPanda expansion failed: #{inspect(reason)}")
        ast

      nil ->
        Logger.debug("ExPanda expansion timed out after #{@expand_timeout_ms}ms")
        ast
    end
  rescue
    e ->
      Logger.debug("ExPanda expansion raised: #{inspect(e)}")
      ast
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

  # Redirects :standard_error to a disposable StringIO for the duration of
  # `fun`, so :elixir_expand diagnostics don't leak to the user's terminal.
  defp with_quiet_stderr(fun) do
    {:ok, sink} = StringIO.open("")
    original = Process.whereis(:standard_error)
    Process.unregister(:standard_error)
    Process.register(sink, :standard_error)

    try do
      fun.()
    after
      Process.unregister(:standard_error)
      Process.register(original, :standard_error)
      StringIO.close(sink)
    end
  end

  # Walk the module AST and expand each def/defp as a whole form
  # (so ExPanda registers function parameters before expanding the body).

  defp expand_defs({:defmodule, meta, [name, [do: body]]}) do
    {:defmodule, meta, [name, [do: expand_defs(body)]]}
  end

  defp expand_defs({:__block__, meta, exprs}) do
    {:__block__, meta, Enum.map(exprs, &expand_defs/1)}
  end

  defp expand_defs({kind, _meta, [original_head, _original_kw]} = def_form)
       when kind in [:def, :defp] do
    case expand_node(def_form) do
      {^kind, expanded_meta, [_expanded_head, expanded_kw]} ->
        # Preserve the original function head (including guards) so that
        # Guard.refine can recognise `is_integer(x)`, `and`, etc.
        # The compiler expansion rewrites guards into case/:erlang forms
        # that the inference engine does not understand.
        {kind, expanded_meta, [original_head, expanded_kw]}

      _other ->
        # Expansion returned something unexpected; keep original.
        def_form
    end
  end

  defp expand_defs(other), do: other
end
