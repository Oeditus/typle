defmodule Typle.Unstable.CompilerHook do
  @moduledoc false
  # Hooks into the Elixir compiler to capture per-expression type information.
  #
  # This module depends on private Elixir compiler internals and is expected
  # to break across Elixir versions. All calls are wrapped in try/rescue.

  alias Typle.Beam
  alias Typle.Unstable.TypeCapture

  @doc """
  Compiles the given file with type capture enabled.

  Returns the captured type map or an error.
  """
  @spec compile_with_capture(String.t()) :: {:ok, map()} | {:error, term()}
  def compile_with_capture(file) do
    TypeCapture.init()

    try do
      # Suppress "redefining module" warnings during replay
      prev_ignore = Code.get_compiler_option(:ignore_module_conflict)
      Code.put_compiler_option(:ignore_module_conflict, true)
      Code.put_compiler_option(:tracers, [__MODULE__])

      _result =
        Kernel.ParallelCompiler.compile([file],
          return_diagnostics: true,
          beam_timestamp: nil
        )

      Code.put_compiler_option(:tracers, [])
      Code.put_compiler_option(:ignore_module_conflict, prev_ignore || false)

      captures = TypeCapture.all()

      # Convert internal type representations to Typle.Type
      type_map =
        Map.new(captures, fn {{line, col}, type_repr} ->
          {{line, col}, decode_captured_type(type_repr)}
        end)

      {:ok, type_map}
    rescue
      e ->
        Code.put_compiler_option(:tracers, [])
        Code.put_compiler_option(:ignore_module_conflict, false)
        {:error, {:compiler_hook_failed, Exception.message(e)}}
    end
  end

  # -- Tracer callback -------------------------------------------------------

  @doc false
  def trace({:on_module, _bytecode, _opts}, env) do
    # When a module finishes compilation, attempt to extract
    # type information from the compiler's internal state.
    try do
      extract_types_from_compiler(env.module)
    rescue
      _ -> :ok
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  # -- Private ---------------------------------------------------------------

  defp extract_types_from_compiler(module) do
    # Attempt to read the just-compiled module's ExCk data from the beam
    # that was just written. This gives us function-level signatures which
    # we record as types at function definition positions.
    case Beam.read_signatures(module) do
      {:ok, signatures} ->
        Enum.each(signatures, fn %{fun: fun, arity: arity, clauses: clauses} ->
          # Record function signature -- we use {0, 0} as a convention
          # for function-level types, since we don't have the exact line
          TypeCapture.record(0, 0, {:function_sig, module, fun, arity, clauses})
        end)

      _ ->
        :ok
    end
  end

  defp decode_captured_type({:function_sig, _mod, _fun, _arity, clauses}) do
    Typle.Type.function(clauses)
  end

  defp decode_captured_type(type_repr) when is_map(type_repr) do
    Beam.decode_type(type_repr)
  end

  defp decode_captured_type(_), do: Typle.Type.dynamic()
end
