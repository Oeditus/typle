defmodule Typle.Unstable do
  @moduledoc """
  Opt-in layer that hooks into the compiler's private type checking
  infrastructure for deeper type inference.

  **WARNING**: This module depends on private Elixir compiler APIs that
  may change without notice between Elixir versions. It is only tested
  with Elixir 1.20.x. If the private APIs change, this module will
  degrade gracefully to the stable inference engine.

  ## Usage

      Typle.Unstable.type_at("lib/my_app/user.ex", 15, 5)
      Typle.Unstable.types_for(MyApp.User)

  """

  alias Typle.Type
  alias Typle.Unstable.{CompilerHook, TypeCapture}

  @compatible_versions ["1.20"]

  @doc """
  Returns the inferred type at the given file position using compiler replay.

  Falls back to stable inference if the compiler hook fails.
  """
  @spec type_at(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Type.t()} | {:error, term()}
  def type_at(file, line, col) do
    with :ok <- check_version(),
         {:ok, type_map} <- types_for_file(file) do
      case Map.get(type_map, {line, col}) do
        nil -> {:error, :no_type_at_position}
        type -> {:ok, type}
      end
    end
  end

  @doc """
  Returns all inferred types for a module using compiler replay.

  Falls back to stable inference if the compiler hook fails.
  """
  @spec types_for(module()) :: {:ok, Typle.Inference.type_map()} | {:error, term()}
  def types_for(module) do
    with :ok <- check_version() do
      source =
        try do
          module.module_info(:compile)[:source]
        rescue
          _ -> nil
        end

      case source do
        nil -> {:error, {:no_source, module}}
        path -> types_for_file(List.to_string(path))
      end
    end
  end

  # -- Private ---------------------------------------------------------------

  defp types_for_file(file) do
    TypeCapture.init()

    case CompilerHook.compile_with_capture(file) do
      {:ok, captures} ->
        {:ok, captures}

      {:error, _reason} ->
        # Fall back to stable inference
        Typle.Inference.infer_file(file)
    end
  end

  defp check_version do
    version = System.version()
    major_minor = version |> String.split(".") |> Enum.take(2) |> Enum.join(".")

    if major_minor in @compatible_versions do
      :ok
    else
      {:error, {:unsupported_elixir_version, version, @compatible_versions}}
    end
  end
end
