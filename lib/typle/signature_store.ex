defmodule Typle.SignatureStore do
  @moduledoc """
  ETS-backed cache of function type signatures.

  Pre-loads function signatures from compiled `.beam` files for the
  project and all dependencies. Used by the inference engine to look up
  return types for remote function calls.
  """

  alias Typle.{Beam, Type}

  @table :typle_signatures

  @doc """
  Initializes the signature store. Creates the ETS table if it does not exist.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Loads signatures for all `.beam` files found under `build_path`.

  Typically called with `Mix.Project.build_path()` to load the current
  project and its dependencies.
  """
  @spec load_project(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_project(build_path) do
    init()

    if File.dir?(build_path) do
      count =
        build_path
        |> beam_files()
        |> Task.async_stream(&load_beam_file/1, max_concurrency: System.schedulers_online())
        |> Enum.reduce(0, fn
          {:ok, n}, acc -> acc + n
          _, acc -> acc
        end)

      {:ok, count}
    else
      # A missing build path used to return `{:ok, 0}`, which is
      # indistinguishable from "the project simply has no beams".
      {:error, {:not_a_directory, build_path}}
    end
  end

  # Only the project's own output plus its dependencies' output -- not every
  # `.beam` reachable from the build root, which pulled in unrelated apps and
  # loaded thousands of rows nobody would ever look up.
  defp beam_files(build_path) do
    [Path.join(build_path, "lib/**/*.beam"), Path.join([build_path, "..", "lib", "**", "*.beam"])]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
  end

  @doc """
  Loads signatures for a single module.
  """
  @spec load_module(module()) :: :ok | {:error, term()}
  def load_module(module) do
    init()

    case Beam.read_signatures(module) do
      {:ok, signatures} ->
        Enum.each(signatures, fn %{fun: fun, arity: arity, clauses: clauses} ->
          :ets.insert(@table, {{module, fun, arity}, clauses})
        end)

        :ok

      error ->
        error
    end
  end

  @doc """
  Looks up the signature clauses for `module.function/arity`.
  """
  @spec lookup(module(), atom(), non_neg_integer()) :: {:ok, [{[Type.t()], Type.t()}]} | :error
  def lookup(module, function, arity) do
    init()

    case :ets.lookup(@table, {module, function, arity}) do
      [{_, clauses}] -> {:ok, clauses}
      [] -> try_load_and_lookup(module, function, arity)
    end
  end

  @doc """
  Given concrete argument types, finds the best matching clause and returns
  its return type. Falls back to `dynamic()` if no clause matches.
  """
  @spec return_type(module(), atom(), non_neg_integer(), [Type.t()]) :: Type.t()
  def return_type(module, function, arity, _arg_types) do
    case lookup(module, function, arity) do
      {:ok, clauses} ->
        # For now, return the union of all clause return types.
        # A more precise implementation would match arg_types against
        # each clause's argument types and select the best match.
        ret_types = Enum.map(clauses, fn {_args, ret} -> ret end)

        case ret_types do
          [single] -> single
          many -> Type.union(many)
        end

      :error ->
        Type.dynamic()
    end
  end

  @doc "Clears all cached signatures."
  @spec clear() :: :ok
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # -- Private ---------------------------------------------------------------

  defp load_beam_file(beam_path) do
    case Beam.read_signatures(beam_path) do
      {:ok, signatures} ->
        # Resolve the module name from the beam itself rather than from the
        # filename. `String.to_atom/1` on a basename would mint a permanent atom
        # for every beam under the build path (4416 of them in this repo) and
        # would silently mis-key any module whose name does not match its file.
        module = beam_module(beam_path)

        Enum.each(signatures, fn %{fun: fun, arity: arity, clauses: clauses} ->
          :ets.insert(@table, {{module, fun, arity}, clauses})
        end)

        length(signatures)

      _ ->
        0
    end
  end

  # Prefers the atom the BEAM chunk already carries; falls back to the
  # filename only when the chunk is unreadable.
  #
  # `:beam_lib.info/1` returns a bare keyword list on success (or
  # `{:error, :beam_lib, reason}`), not an `{:ok, info}` tuple.
  defp beam_module(beam_path) do
    case :beam_lib.info(String.to_charlist(beam_path)) do
      info when is_list(info) -> Keyword.get(info, :module) || filename_module(beam_path)
      _ -> filename_module(beam_path)
    end
  end

  defp filename_module(beam_path) do
    beam_path |> Path.basename(".beam") |> String.to_atom()
  end

  defp try_load_and_lookup(module, function, arity) do
    case load_module(module) do
      :ok ->
        case :ets.lookup(@table, {module, function, arity}) do
          [{_, clauses}] -> {:ok, clauses}
          [] -> :error
        end

      _ ->
        :error
    end
  end
end
