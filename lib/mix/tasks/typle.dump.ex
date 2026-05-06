defmodule Mix.Tasks.Typle.Dump do
  @shortdoc "Dump all inferred types for a module or file"
  @moduledoc """
  Dumps all inferred expression types for a module or file.

  ## Usage

      mix typle.dump MyApp.User
      mix typle.dump lib/my_app/user.ex

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
      [target] ->
        dump(target, format, unstable?)

      _ ->
        Mix.shell().error(
          "Usage: mix typle.dump <Module | file.ex> [--format text|json] [--unstable]"
        )
    end
  end

  defp dump(target, format, unstable?) do
    result =
      if String.ends_with?(target, ".ex") or String.ends_with?(target, ".exs") do
        if unstable? do
          Typle.Unstable.types_for(find_module(target))
        else
          Typle.types_for_file(target)
        end
      else
        module = Module.concat([target])

        if unstable? do
          Typle.Unstable.types_for(module)
        else
          Typle.types_for(module)
        end
      end

    case result do
      {:ok, type_map} -> output(type_map, format)
      {:error, reason} -> Mix.shell().error("Error: #{inspect(reason)}")
    end
  end

  defp output(type_map, "text") do
    type_map
    |> Enum.sort_by(fn {{line, col}, _} -> {line, col} end)
    |> Enum.group_by(fn {{line, _}, _} -> line end)
    |> Enum.sort_by(fn {line, _} -> line end)
    |> Enum.each(fn {line, entries} ->
      entries
      |> Enum.sort_by(fn {{_, col}, _} -> col end)
      |> Enum.each(fn {{_, col}, type} ->
        Mix.shell().info("  #{line}:#{col}  #{Typle.Type.to_string(type)}")
      end)
    end)
  end

  defp output(type_map, "json") do
    entries =
      type_map
      |> Enum.sort_by(fn {{line, col}, _} -> {line, col} end)
      |> Enum.map(fn {{line, col}, type} ->
        %{line: line, column: col, type: Typle.Type.to_string(type)}
      end)

    Mix.shell().info(:json.encode(%{types: entries}) |> IO.iodata_to_binary())
  end

  defp find_module(file) do
    file
    |> Path.rootname()
    |> String.replace(~r{^lib/}, "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Module.concat()
  end
end
