defmodule Typle.InferenceTest do
  use ExUnit.Case

  alias Typle.Inference

  @fixture_path Path.expand("../support/sample_module.ex", __DIR__)

  describe "infer_file/1" do
    test "returns a type map for a valid source file" do
      assert {:ok, type_map} = Inference.infer_file(@fixture_path)
      assert is_map(type_map)
      assert map_size(type_map) > 0
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Inference.infer_file("/no/such/file.ex")
    end

    test "infers types for expressions in the sample module" do
      {:ok, type_map} = Inference.infer_file(@fixture_path)

      # The file has expressions starting at line 6+, so we should have entries
      lines = type_map |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      assert [_ | _] = lines
    end

    test "infers correct type for integer literal in the fixture" do
      {:ok, type_map} = Inference.infer_file(@fixture_path)

      # Line 23: `defp secret, do: 42` -- the 42 literal should be integer
      integer_entries =
        Enum.filter(type_map, fn {_pos, type} ->
          type.kind == :integer and not type.dynamic?
        end)

      assert [_ | _] = integer_entries
    end
  end
end
