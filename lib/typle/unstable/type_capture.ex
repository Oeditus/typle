defmodule Typle.Unstable.TypeCapture do
  @moduledoc false

  @table :typle_type_capture

  @doc "Initializes the capture ETS table."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Records a type for a position."
  def record(line, col, type_repr) do
    :ets.insert(@table, {{line, col}, type_repr})
    :ok
  end

  @doc "Retrieves all captured types as a map."
  def all do
    if :ets.whereis(@table) != :undefined do
      :ets.tab2list(@table) |> Map.new()
    else
      %{}
    end
  end

  @doc "Retrieves the type at a given position."
  def get(line, col) do
    case :ets.lookup(@table, {line, col}) do
      [{_, type}] -> {:ok, type}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end
end
