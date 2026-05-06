defmodule Typle.ExprMap do
  @moduledoc """
  Post-hoc expression extraction from source files.

  Parses the original (unexpanded) AST and walks it to build a map of
  `{line, col} => expression_string` for every AST node that carries
  position metadata.

  This is primarily used by the unstable inference path, which captures
  types via compiler replay but has no access to expression strings.
  """

  @type expr_map :: %{{non_neg_integer(), non_neg_integer()} => String.t()}

  @doc """
  Extracts a map of `{line, col} => expression_string` from a source file.

  Parses the file without macro expansion and records `Macro.to_string/1`
  for each AST node that has `:line` and `:column` metadata.
  """
  @spec extract(String.t()) :: {:ok, expr_map()} | {:error, term()}
  def extract(file_path) do
    with {:ok, source} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {:ok, walk(ast)}
    end
  end

  @doc """
  Looks up the expression string at `{line, col}` in a source file.

  Returns `nil` when no AST node starts at that position.
  """
  @spec expr_at(String.t(), non_neg_integer(), non_neg_integer()) :: String.t() | nil
  def expr_at(file_path, line, col) do
    case extract(file_path) do
      {:ok, map} -> Map.get(map, {line, col})
      _ -> nil
    end
  end

  # -- Private ---------------------------------------------------------------

  defp walk(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, %{}, fn
        {_form, meta, _args} = node, acc when is_list(meta) ->
          line = Keyword.get(meta, :line, 0)
          col = Keyword.get(meta, :column, 0)

          if line > 0 and col > 0 do
            {node, Map.put_new(acc, {line, col}, Macro.to_string(node))}
          else
            {node, acc}
          end

        other, acc ->
          {other, acc}
      end)

    acc
  end
end
