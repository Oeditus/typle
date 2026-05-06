defmodule Typle.InferenceTest do
  use ExUnit.Case

  alias Typle.Inference

  @fixture_path Path.expand("../support/sample_module.ex", __DIR__)
  @macro_fixture_path Path.expand("../support/macro_module.ex", __DIR__)

  describe "infer_file/1" do
    test "returns a type map for a valid source file" do
      assert {:ok, %{types: types, exprs: exprs}} = Inference.infer_file(@fixture_path)
      assert is_map(types)
      assert map_size(types) > 0
      assert is_map(exprs)
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Inference.infer_file("/no/such/file.ex")
    end

    test "infers types for expressions in the sample module" do
      {:ok, %{types: types}} = Inference.infer_file(@fixture_path)

      # The file has expressions starting at line 6+, so we should have entries
      lines = types |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      assert [_ | _] = lines
    end

    test "infers integer type for guard-refined variables" do
      {:ok, %{types: types}} = Inference.infer_file(@fixture_path)

      # `def add(a, b) when is_integer(a) and is_integer(b)` refines
      # `a` and `b` to integer(); these are recorded when referenced in the body.
      integer_entries =
        Enum.filter(types, fn {_pos, type} ->
          type.kind == :integer
        end)

      assert [_ | _] = integer_entries
    end

    test "narrows type through match operator in function head" do
      {:ok, %{types: types}} = Inference.infer_file(@fixture_path)

      # Line 21: def identity(%{} = x), do: x
      # x at column 30 should be map (narrowed by %{} match)
      body_x = Map.get(types, {21, 30})
      assert body_x != nil, "expected type recorded at {21, 30} (body x)"
      assert body_x.kind == :map
    end

    test "decomposes case pattern types from Integer.parse" do
      {:ok, %{types: types}} = Inference.infer_file(@fixture_path)

      # Line 16: {num, _rest} -> {:ok, num}
      # num in pattern at column 8 should be integer (from tuple decomposition)
      pattern_num = Map.get(types, {16, 8})
      assert pattern_num != nil, "expected type recorded at {16, 8} (pattern num)"
      assert pattern_num.kind == :integer

      # num in body at column 29 should also be integer (from scope lookup)
      body_num = Map.get(types, {16, 29})
      assert body_num != nil, "expected type recorded at {16, 29} (body num)"
      assert body_num.kind == :integer
    end

    test "records expression strings alongside types" do
      {:ok, %{types: types, exprs: exprs}} = Inference.infer_file(@fixture_path)

      # All typed positions should have corresponding expression strings
      typed_positions_with_exprs =
        Enum.count(types, fn {pos, _type} -> Map.has_key?(exprs, pos) end)

      assert typed_positions_with_exprs > 0

      # Line 16, col 8: pattern variable `num` should have expr "num"
      assert Map.get(exprs, {16, 8}) == "num"

      # Line 16, col 29: body variable `num` should have expr "num"
      assert Map.get(exprs, {16, 29}) == "num"
    end
  end

  describe "macro expansion inference" do
    test "infers types through expanded pipe chains" do
      {:ok, %{types: types}} = Inference.infer_file(@macro_fixture_path)
      assert is_map(types)
      assert map_size(types) > 0

      # The piped/1 function uses Integer.to_string |> String.upcase.
      # After macro expansion, these resolve to remote calls with known return types.
      has_binary =
        Enum.any?(types, fn {_pos, type} ->
          type.kind == :binary
        end)

      assert has_binary, "Expected at least one binary type from pipe chain inference"
    end

    test "infers types for expanded unless expression" do
      {:ok, %{types: types}} = Inference.infer_file(@macro_fixture_path)

      # The conditional/1 and negated/1 functions use unless/if which produce
      # union result types. Verify we get non-dynamic union or concrete types.
      non_dynamic_entries =
        Enum.filter(types, fn {_pos, type} ->
          type.kind != :dynamic or type.dynamic?
        end)

      assert [_ | _] = non_dynamic_entries
    end

    test "produces more type entries than lines in the macro fixture" do
      {:ok, %{types: types}} = Inference.infer_file(@macro_fixture_path)

      # With macro expansion, we should get type entries for expressions
      # that were previously hidden inside macro calls.
      assert map_size(types) > 5
    end
  end
end
