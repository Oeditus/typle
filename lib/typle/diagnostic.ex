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
    try do
      result =
        Kernel.ParallelCompiler.compile(file_paths,
          return_diagnostics: true,
          beam_timestamp: nil
        )

      diagnostics =
        case result do
          {:ok, _modules, warnings} -> warnings
          {:error, errors, warnings} -> errors ++ warnings
        end

      infos =
        diagnostics
        |> Enum.filter(&type_diagnostic?/1)
        |> Enum.map(&parse_diagnostic/1)

      {:ok, infos}
    rescue
      e -> {:error, {:compilation_failed, Exception.message(e)}}
    end
  end

  @doc """
  Captures diagnostics for a single file.
  """
  @spec capture_file(String.t()) :: {:ok, [diagnostic_info()]} | {:error, term()}
  def capture_file(file_path), do: capture([file_path])

  # -- Private ---------------------------------------------------------------

  defp type_diagnostic?(%{message: message}) when is_binary(message) do
    String.contains?(message, "typing violation") or
      String.contains?(message, "incompatible types") or
      String.contains?(message, "unknown key") or
      String.contains?(message, "given types:")
  end

  defp type_diagnostic?(%{message: message}) when is_list(message) do
    text = IO.chardata_to_string(message)

    String.contains?(text, "typing violation") or
      String.contains?(text, "incompatible types") or
      String.contains?(text, "unknown key") or
      String.contains?(text, "given types:")
  end

  defp type_diagnostic?(_), do: false

  defp parse_diagnostic(%{} = diag) do
    message =
      case diag.message do
        msg when is_binary(msg) -> msg
        msg when is_list(msg) -> IO.chardata_to_string(msg)
        _ -> ""
      end

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
