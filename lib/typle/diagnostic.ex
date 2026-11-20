defmodule Typle.Diagnostic do
  @moduledoc """
  Captures and parses compiler diagnostics for type information.

  When the Elixir 1.20 compiler detects a type violation, it emits
  structured diagnostics containing the given and expected types.
  This module captures those diagnostics and extracts type data.
  """

  @type diagnostic_info :: %{
          file: String.t(),
          position: {non_neg_integer(), non_neg_integer()},
          message: String.t(),
          given_type: String.t() | nil,
          expected_type: String.t() | nil
        }

  @doc """
  Compiles the given files and captures any type-related diagnostics.

  Returns a list of parsed diagnostic info maps.
  """
  @spec capture(list(String.t())) :: {:ok, [diagnostic_info()]} | {:error, term()}
  def capture(file_paths) when is_list(file_paths) do
    result =
      Kernel.ParallelCompiler.compile(file_paths,
        return_diagnostics: true,
        beam_timestamp: nil
      )

    # `ParallelCompiler.compile/2` returns the warnings as a *map*
    # (`%{compile_warnings: [...], runtime_warnings: [...]}`), not a list. The
    # previous `errors ++ warnings` therefore raised on every call that produced
    # an error, and `warnings` alone fed a map into `Enum.filter/2`.
    diagnostics =
      case result do
        {:ok, _modules, warnings} -> diagnostics_list(warnings)
        {:error, errors, warnings} -> diagnostics_list(errors) ++ diagnostics_list(warnings)
      end

    infos =
      diagnostics
      |> Enum.filter(&type_diagnostic?/1)
      |> Enum.map(&parse_diagnostic/1)

    {:ok, infos}
  rescue
    e -> {:error, {:compilation_failed, Exception.message(e)}}
  end

  @doc """
  Captures diagnostics for a single file.
  """
  @spec capture_file(String.t()) :: {:ok, [diagnostic_info()]} | {:error, term()}
  def capture_file(file_path), do: capture([file_path])

  # -- Private ---------------------------------------------------------------

  # Normalises the compiler's diagnostics container to a flat list. Depending on
  # the Elixir version and outcome this is either a plain list or a map of
  # `%{compile_warnings: [...], runtime_warnings: [...]}`.
  defp diagnostics_list(list) when is_list(list), do: list

  defp diagnostics_list(%{} = map) do
    Map.get(map, :compile_warnings, []) ++ Map.get(map, :runtime_warnings, [])
  end

  @type_markers [
    "typing violation",
    "incompatible types",
    "unknown key",
    "given types:"
  ]

  defp type_diagnostic?(%{message: message}) do
    text = message_text(message)
    Enum.any?(@type_markers, &String.contains?(text, &1))
  end

  defp type_diagnostic?(_), do: false

  defp message_text(message) when is_binary(message), do: message
  defp message_text(message) when is_list(message), do: IO.chardata_to_string(message)
  defp message_text(_), do: ""

  defp parse_diagnostic(%{} = diag) do
    message = message_text(Map.get(diag, :message))

    %{
      file: Map.get(diag, :file, ""),
      position: Map.get(diag, :position, {0, 0}),
      message: message,
      given_type: extract_given_type(message),
      expected_type: extract_expected_type(message)
    }
  end

  defp extract_given_type(message) do
    case Regex.run(~r/given types?:\s*\n\s*(.+)/m, message) do
      [_, type_str] -> String.trim(type_str)
      _ -> nil
    end
  end

  defp extract_expected_type(message) do
    case Regex.run(~r/but expected one of:\s*\n\s*(.+)/m, message) do
      [_, type_str] -> String.trim(type_str)
      _ -> nil
    end
  end
end
