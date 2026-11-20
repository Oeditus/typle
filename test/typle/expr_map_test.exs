defmodule Typle.ExprMapTest do
  use ExUnit.Case, async: true

  alias Typle.ExprMap

  @fixture Path.expand("../support/sample_module.ex", __DIR__)

  describe "extract/1" do
    test "returns a position-keyed map of expression strings" do
      assert {:ok, map} = ExprMap.extract(@fixture)
      assert is_map(map)
      assert map_size(map) > 0
      assert Enum.all?(map, fn {pos, str} -> is_tuple(pos) and is_binary(str) end)
    end

    test "records the function head and its arguments" do
      {:ok, map} = ExprMap.extract(@fixture)
      assert Map.get(map, {6, 7}) == "add(a, b)"
    end

    test "returns an error for a missing file" do
      assert {:error, _} = ExprMap.extract("/no/such/file.ex")
    end

    test "returns an error for unparseable source" do
      path = Path.join(System.tmp_dir!(), "typle_bad_#{System.unique_integer([:positive])}.ex")
      File.write!(path, "defmodule Broken do\n  def oops(\nend\n")

      try do
        assert {:error, _} = ExprMap.extract(path)
      after
        File.rm(path)
      end
    end

    test "skips nodes without position metadata" do
      path = Path.join(System.tmp_dir!(), "typle_meta_#{System.unique_integer([:positive])}.ex")
      File.write!(path, "defmodule NoMeta do\n  def f(x), do: x\nend\n")

      try do
        {:ok, map} = ExprMap.extract(path)
        # Every recorded position must have a real, positive line.
        assert Enum.all?(map, fn {{line, _col}, _} -> line > 0 end)
      after
        File.rm(path)
      end
    end
  end

  describe "expr_at/3" do
    test "returns the expression string at a known position" do
      assert ExprMap.expr_at(@fixture, 6, 7) == "add(a, b)"
    end

    test "returns nil for a position with no node" do
      # Line 3 of the fixture is a blank line inside the module body.
      assert ExprMap.expr_at(@fixture, 3, 1) == nil
    end

    test "returns nil for a missing file" do
      assert ExprMap.expr_at("/no/such/file.ex", 1, 1) == nil
    end
  end
end
