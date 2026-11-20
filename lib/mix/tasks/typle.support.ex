defmodule Mix.Tasks.Typle.Support do
  @moduledoc false
  # Shared plumbing for `mix typle` and `mix typle.dump`.
  #
  # Both tasks accept the same `--format` / `--unstable` options and the same
  # `file:line[:col]` location grammar, and both must fail loudly: a type query
  # that cannot answer is a failed check, not a successful one. Keeping the
  # option validation and error rendering in one place stops the two tasks from
  # drifting apart.

  @formats ["text", "json"]

  @doc "Returns the accepted `--format` values."
  @spec formats() :: [String.t()]
  def formats, do: @formats

  @doc """
  Parses and validates the shared options, raising on anything unsupported.

  Returns `{format, unstable?}`.
  """
  @spec parse_options(keyword()) :: {String.t(), boolean()}
  def parse_options(opts) do
    format = Keyword.get(opts, :format, "text")

    unless format in @formats do
      Mix.raise(
        "Unknown format: #{inspect(format)}. Expected one of: #{Enum.join(@formats, ", ")}"
      )
    end

    {format, Keyword.get(opts, :unstable, false)}
  end

  @doc """
  Parses a `file:line` or `file:line:col` location.

  Returns `{:ok, file, line}`, `{:ok, file, line, col}`, or `:error`.
  """
  @spec parse_location(String.t()) ::
          {:ok, String.t(), integer()} | {:ok, String.t(), integer(), integer()} | :error
  def parse_location(location) do
    case String.split(location, ":") do
      [file, line_str, col_str] ->
        with {line, ""} <- Integer.parse(line_str),
             {col, ""} <- Integer.parse(col_str) do
          {:ok, file, line, col}
        else
          _ -> :error
        end

      [file, line_str] ->
        case Integer.parse(line_str) do
          {line, ""} -> {:ok, file, line}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @doc "Turns an error reason into a human-readable sentence."
  @spec describe(term(), keyword()) :: String.t()
  def describe(:enoent, context) do
    case Keyword.get(context, :file) do
      nil -> "No such file."
      file -> "No such file: #{file}"
    end
  end

  def describe(:no_type_at_position, context) do
    file = Keyword.get(context, :file, "the file")

    "No type recorded at #{location(context)}. " <>
      "Try `mix typle.dump #{file}` to list every position that does have a type."
  end

  def describe({:module_not_available, module}, _context) do
    "Module #{inspect(module)} is not compiled or not available. " <>
      "Run `mix compile` first, or pass a source file path instead."
  end

  def describe({:no_source, module}, _context) do
    "Module #{inspect(module)} has no recorded source path. " <>
      "Pass the source file path directly instead."
  end

  def describe({:unsupported_checker_version, version}, _context) do
    "This Elixir version writes ExCk format #{inspect(version)}, which this " <>
      "version of Typle does not support. Supported: v7, v8. " <>
      "Please open an issue at https://github.com/Oeditus/typle/issues"
  end

  def describe({:file_not_found, path}, _context), do: "No such file: #{path}"

  def describe(reason, _context), do: "Type query failed: #{inspect(reason)}"

  defp location(context) do
    file = Keyword.get(context, :file, "?")
    line = Keyword.get(context, :line, "?")
    col = Keyword.get(context, :col, "?")

    "#{file}:#{line}:#{col}"
  end
end
