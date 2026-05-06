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

    beam_files =
      build_path
      |> Path.join("**/*.beam")
      |> Path.wildcard()

    count =
      beam_files
      |> Task.async_stream(&load_beam_file/1, max_concurrency: System.schedulers_online())
      |> Enum.reduce(0, fn
        {:ok, n}, acc -> acc + n
        _, acc -> acc
      end)

    {:ok, count}
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
        # Extract module name from beam filename
        module =
          beam_path
          |> Path.basename(".beam")
          |> String.to_atom()

        Enum.each(signatures, fn %{fun: fun, arity: arity, clauses: clauses} ->
          :ets.insert(@table, {{module, fun, arity}, clauses})
        end)

        length(signatures)

      _ ->
        0
    end
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
