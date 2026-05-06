defmodule TypleTest do
  use ExUnit.Case

  alias Typle.Type

  @fixture_path Path.expand("support/sample_module.ex", __DIR__)

  describe "signatures/1" do
    test "reads signatures from a stdlib module" do
      assert {:ok, sigs} = Typle.signatures(Integer)
      assert is_list(sigs)
      assert length(sigs) > 0
    end

    test "returns error for unknown module" do
      assert {:error, _} = Typle.signatures(NoSuchModuleAtAll)
    end
  end

  describe "return_type/3" do
    test "returns inferred return type for known function" do
      type = Typle.return_type(Integer, :to_string, 1)
      assert %Type{kind: :binary, dynamic?: true} = type
    end

    test "returns dynamic for unknown function" do
      type = Typle.return_type(NoSuchMod, :no_fun, 0)
      assert %Type{dynamic?: true} = type
    end
  end

  describe "types_for_file/1" do
    test "infers types for a source file" do
      assert {:ok, type_map} = Typle.types_for_file(@fixture_path)
      assert is_map(type_map)
      assert map_size(type_map) > 0
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Typle.types_for_file("/no/such/file.ex")
    end
  end

  describe "type_at/3" do
    test "returns error for position with no recorded type" do
      assert {:error, :no_type_at_position} = Typle.type_at(@fixture_path, 1, 1)
    end
  end
end
