defmodule Mix.Tasks.Typle.Dump do
  @shortdoc "Dump all inferred types for a module or file"
  @moduledoc """
  Dumps all inferred expression types for a module or file.

  ## Usage

      mix typle.dump MyApp.User
      mix typle.dump lib/my_app/user.ex
      mix typle.dump lib/my_app/user.ex:15

  ## Options

    * `--unstable` - use the unstable compiler replay for deeper inference
    * `--format text|json` - output format (default: text)

  ## Exit status

  Exits non-zero when the target cannot be resolved, so the task is safe to use
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
      [target] ->
        dump(target, format, unstable?)

      _ ->
        Mix.raise(
          "Usage: mix typle.dump <Module | file.ex[:line]> [--format text|json] [--unstable]"
        )
    end
  end

  defp dump(target, format, unstable?) do
    case resolve_target(target) do
      {:file, file, nil} ->
        file |> Typle.types_for_file(unstable: unstable?) |> output(format)

      {:file, file, line} ->
        file |> Typle.types_for_file(unstable: unstable?) |> output_line(line, format)

      {:module, module} ->
        module |> Typle.types_for(module_opts(unstable?)) |> output(format)
    end
  end

  defp module_opts(true), do: [unstable: true]
  defp module_opts(false), do: []

  # Accepts `Module`, `path.ex`, and `path.ex:line` -- the same location grammar
  # `mix typle` uses, so the two tasks do not disagree about arguments.
  defp resolve_target(target) do
    case Support.parse_location(target) do
      {:ok, file, line} ->
        {:file, file, line}

      {:ok, file, line, _col} ->
        {:file, file, line}

      :error ->
        if source_file?(target),
          do: {:file, target, nil},
          else: {:module, Module.concat([target])}
    end
  end

  defp source_file?(target) do
    String.ends_with?(target, ".ex") or String.ends_with?(target, ".exs")
  end

  defp output_line({:ok, type_map}, line, format) do
    case Enum.filter(type_map, fn {{l, _c}, _v} -> l == line end) do
      [] ->
        Mix.shell().info("No types recorded on line #{line}.")

      _entries ->
        output({:ok, type_map}, format)
    end
  end

  defp output_line({:error, reason}, _line, _format), do: Mix.raise(Support.describe(reason, []))

  defp output({:ok, type_map}, "text") do
    type_map
    |> Enum.sort_by(fn {{line, col}, _} -> {line, col} end)
    |> Enum.group_by(fn {{line, _}, _} -> line end)
    |> Enum.sort_by(fn {line, _} -> line end)
    |> Enum.each(fn {line, entries} ->
      entries
      |> Enum.sort_by(fn {{_, col}, _} -> col end)
      |> Enum.each(fn {{_, col}, %{type: type, expr: expr}} ->
        expr_suffix = if expr, do: "  (#{expr})", else: ""
        Mix.shell().info("  #{line}:#{col}  #{Typle.Type.to_string(type)}#{expr_suffix}")
      end)
    end)
  end

  defp output({:ok, type_map}, "json") do
    entries =
      type_map
      |> Enum.sort_by(fn {{line, col}, _} -> {line, col} end)
      |> Enum.map(fn {{line, col}, %{type: type, expr: expr}} ->
        %{line: line, column: col, type: Typle.Type.to_string(type), expr: expr}
      end)

    Mix.shell().info(:json.encode(%{types: entries}) |> IO.iodata_to_binary())
  end

  defp output({:error, reason}, _format), do: Mix.raise(Support.describe(reason, []))
end
