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

  ## Exit status

  Exits non-zero when the query cannot be answered, so the task is safe to use
  as a check in CI.
  """
  use Mix.Task

  alias Mix.Tasks.Typle.Support

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [unstable: :boolean, format: :string],
        aliases: [u: :unstable, f: :format]
      )

    {format, unstable?} = Support.parse_options(opts)

    case positional do
      [location] ->
        query(location, format, unstable?)

      _ ->
        Mix.raise("Usage: mix typle <file>:<line>[:<col>] [--format text|json] [--unstable]")
    end
  end

  defp query(location, format, unstable?) do
    case Support.parse_location(location) do
      {:ok, file, line, col} ->
        result = Typle.type_at(file, line, col, unstable: unstable?)
        output_result(result, file, line, col, format)

      {:ok, file, line} ->
        result = Typle.types_for_file_with_skipped(file, unstable: unstable?)
        output_line_results(result, file, line, format)

      :error ->
        Mix.raise("Invalid location format. Use file:line or file:line:col")
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

  defp output_result({:error, reason}, file, line, col, _format) do
    Mix.raise(Support.describe(reason, file: file, line: line, col: col))
  end

  defp output_line_results({:ok, type_map, skipped}, file, line, "text") do
    entries = entries_on_line(type_map, line)

    case entries do
      [] ->
        Mix.shell().info(empty_line_hint(type_map, file, line))

      entries ->
        Enum.each(entries, fn {col, type, expr} ->
          expr_suffix = if expr, do: "  (#{expr})", else: ""
          Mix.shell().info("  col #{col}: #{Typle.Type.to_string(type)}#{expr_suffix}")
        end)
    end

    report_skipped(skipped)
  end

  defp output_line_results({:ok, type_map, skipped}, _file, line, "json") do
    entries =
      type_map
      |> entries_on_line(line)
      |> Enum.map(fn {col, type, expr} ->
        %{column: col, type: Typle.Type.to_string(type), expr: expr}
      end)

    payload =
      %{line: line, entries: entries}
      |> maybe_put_skipped(skipped)

    Mix.shell().info(:json.encode(payload) |> IO.iodata_to_binary())
  end

  defp output_line_results({:error, reason}, file, line, _format) do
    Mix.raise(Support.describe(reason, file: file, line: line))
  end

  defp entries_on_line(type_map, line) do
    type_map
    |> Enum.filter(fn {{l, _c}, _v} -> l == line end)
    |> Enum.sort_by(fn {{_l, c}, _v} -> c end)
    |> Enum.map(fn {{_l, col}, %{type: type, expr: expr}} -> {col, type, expr} end)
  end

  # A line with no recorded positions is a dead end unless we say where the
  # nearest answers are -- the data is already in the map.
  defp empty_line_hint(type_map, file, line) do
    case nearest_lines(type_map, line) do
      [] ->
        "No types recorded on line #{line} of #{file}, and no other lines have types either. " <>
          "The file may not have parsed."

      lines ->
        "No types recorded on line #{line} of #{file}. " <>
          "Nearest lines with types: #{Enum.join(lines, ", ")}"
    end
  end

  defp nearest_lines(type_map, line) do
    type_map
    |> Map.keys()
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.sort_by(&abs(&1 - line))
    |> Enum.take(3)
    |> Enum.sort()
  end

  # Inference skips forms it cannot handle rather than failing the file. Say so,
  # otherwise a short result looks like a bug in the query.
  defp report_skipped([]), do: :ok

  defp report_skipped(skipped) do
    count = length(skipped)
    {line, reason} = hd(skipped)

    Mix.shell().info(
      "Note: #{count} top-level form(s) could not be inferred " <>
        "(first at line #{line}: #{short_reason(reason)}). Results above are partial."
    )
  end

  # Exception messages can span many lines; a one-line summary is what a CLI
  # footer can actually show.
  defp short_reason(reason) do
    reason
    |> String.split("\n")
    |> List.first()
    |> String.slice(0, 120)
  end

  defp maybe_put_skipped(payload, []), do: payload

  defp maybe_put_skipped(payload, skipped) do
    Map.put(
      payload,
      :skipped,
      Enum.map(skipped, fn {line, reason} -> %{line: line, reason: short_reason(reason)} end)
    )
  end
end
