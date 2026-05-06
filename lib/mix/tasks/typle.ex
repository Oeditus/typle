defmodule Mix.Tasks.Typle do
  @shortdoc "Query inferred types at a file position"
  @moduledoc """
  Queries the inferred type at a specific position in a source file.

  ## Usage

      mix typle lib/my_app/user.ex:15:5
      mix typle lib/my_app/user.ex:15

  ## Options

    * `--unstable` - use the unstable compiler replay for deeper inference
    * `--format text|json` - output format (default: text)

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [unstable: :boolean, format: :string],
        aliases: [u: :unstable, f: :format]
      )

    format = Keyword.get(opts, :format, "text")
    unstable? = Keyword.get(opts, :unstable, false)

    case positional do
      [location] ->
        query(location, format, unstable?)

      _ ->
        Mix.shell().error(
          "Usage: mix typle <file>:<line>[:<col>] [--format text|json] [--unstable]"
        )
    end
  end

  defp query(location, format, unstable?) do
    case parse_location(location) do
      {:ok, file, line, col} ->
        result = Typle.type_at(file, line, col, unstable: unstable?)
        output_result(result, file, line, col, format)

      {:ok, file, line} ->
        result = Typle.types_for_file(file, unstable: unstable?)
        output_line_results(result, line, format)

      :error ->
        Mix.shell().error("Invalid location format. Use file:line or file:line:col")
    end
  end

  defp parse_location(location) do
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

  defp output_result({:ok, %{type: type, expr: expr}}, file, line, col, "text") do
    expr_suffix = if expr, do: "  (#{expr})", else: ""
    Mix.shell().info("#{file}:#{line}:#{col} :: #{Typle.Type.to_string(type)}#{expr_suffix}")
  end

  defp output_result({:ok, %{type: type, expr: expr}}, file, line, col, "json") do
    data = %{
      file: file,
      line: line,
      column: col,
      type: Typle.Type.to_string(type),
      expr: expr
    }

    Mix.shell().info(:json.encode(data) |> IO.iodata_to_binary())
  end

  defp output_result({:error, reason}, _file, _line, _col, _format) do
    Mix.shell().error("Error: #{inspect(reason)}")
  end

  defp output_line_results({:ok, type_map}, line, "text") do
    type_map
    |> Enum.filter(fn {{l, _c}, _v} -> l == line end)
    |> Enum.sort_by(fn {{_l, c}, _v} -> c end)
    |> Enum.each(fn {{_l, col}, %{type: type, expr: expr}} ->
      expr_suffix = if expr, do: "  (#{expr})", else: ""
      Mix.shell().info("  col #{col}: #{Typle.Type.to_string(type)}#{expr_suffix}")
    end)
  end

  defp output_line_results({:ok, type_map}, line, "json") do
    entries =
      type_map
      |> Enum.filter(fn {{l, _c}, _v} -> l == line end)
      |> Enum.sort_by(fn {{_l, c}, _v} -> c end)
      |> Enum.map(fn {{_l, col}, %{type: type, expr: expr}} ->
        %{column: col, type: Typle.Type.to_string(type), expr: expr}
      end)

    Mix.shell().info(:json.encode(%{line: line, entries: entries}) |> IO.iodata_to_binary())
  end

  defp output_line_results({:error, reason}, _line, _format) do
    Mix.shell().error("Error: #{inspect(reason)}")
  end
end
