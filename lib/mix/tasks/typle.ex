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
        result =
          if unstable? do
            Typle.Unstable.type_at(file, line, col)
          else
            Typle.type_at(file, line, col)
          end

        output_result(result, file, line, col, format)

      {:ok, file, line} ->
        result =
          if unstable? do
            case Typle.Unstable.types_for(find_module(file)) do
              {:ok, _} = ok -> ok
              _ -> Typle.types_for_file(file)
            end
          else
            Typle.types_for_file(file)
          end

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

  defp output_result({:ok, type}, file, line, col, "text") do
    Mix.shell().info("#{file}:#{line}:#{col} :: #{Typle.Type.to_string(type)}")
  end

  defp output_result({:ok, type}, file, line, col, "json") do
    data = %{
      file: file,
      line: line,
      column: col,
      type: Typle.Type.to_string(type)
    }

    Mix.shell().info(:json.encode(data) |> IO.iodata_to_binary())
  end

  defp output_result({:error, reason}, _file, _line, _col, _format) do
    Mix.shell().error("Error: #{inspect(reason)}")
  end

  defp output_line_results({:ok, type_map}, line, "text") do
    type_map
    |> Enum.filter(fn {{l, _c}, _type} -> l == line end)
    |> Enum.sort_by(fn {{_l, c}, _type} -> c end)
    |> Enum.each(fn {{_l, col}, type} ->
      Mix.shell().info("  col #{col}: #{Typle.Type.to_string(type)}")
    end)
  end

  defp output_line_results({:ok, type_map}, line, "json") do
    entries =
      type_map
      |> Enum.filter(fn {{l, _c}, _type} -> l == line end)
      |> Enum.sort_by(fn {{_l, c}, _type} -> c end)
      |> Enum.map(fn {{_l, col}, type} ->
        %{column: col, type: Typle.Type.to_string(type)}
      end)

    Mix.shell().info(:json.encode(%{line: line, entries: entries}) |> IO.iodata_to_binary())
  end

  defp output_line_results({:error, reason}, _line, _format) do
    Mix.shell().error("Error: #{inspect(reason)}")
  end

  defp find_module(file) do
    # Best-effort: derive module name from file path
    file
    |> Path.rootname()
    |> String.replace(~r{^lib/}, "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Module.concat()
  end
end
