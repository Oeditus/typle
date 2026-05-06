defmodule Typle.Inference.BuiltinsTest do
  use ExUnit.Case, async: true

  alias Typle.Inference.Builtins
  alias Typle.Type

  describe "Kernel operators" do
    test "+ returns dynamic(number())" do
      type = Builtins.return_type(Kernel, :+, 2, [Type.integer(), Type.integer()])
      assert type.dynamic?
    end

    test "/ returns dynamic(float())" do
      type = Builtins.return_type(Kernel, :/, 2, [Type.integer(), Type.integer()])
      assert %Type{kind: :float, dynamic?: true} = type
    end

    test "rem returns dynamic(integer())" do
      type = Builtins.return_type(Kernel, :rem, 2, [Type.integer(), Type.integer()])
      assert %Type{kind: :integer, dynamic?: true} = type
    end

    test "== returns dynamic(boolean())" do
      type = Builtins.return_type(Kernel, :==, 2, [Type.integer(), Type.integer()])
      assert type.dynamic?
    end

    test "<> returns dynamic(binary())" do
      type = Builtins.return_type(Kernel, :<>, 2, [Type.binary(), Type.binary()])
      assert %Type{kind: :binary, dynamic?: true} = type
    end

    test "is_integer returns boolean" do
      type = Builtins.return_type(Kernel, :is_integer, 1, [Type.dynamic()])
      assert %Type{kind: :union} = type
    end

    test "length returns dynamic(integer())" do
      type = Builtins.return_type(Kernel, :length, 1, [Type.list()])
      assert %Type{kind: :integer, dynamic?: true} = type
    end
  end

  describe "Integer" do
    test "Integer.to_string/1 returns dynamic(binary())" do
      type = Builtins.return_type(Integer, :to_string, 1, [Type.integer()])
      assert %Type{kind: :binary, dynamic?: true} = type
    end

    test "Integer.parse/1 returns dynamic(:error or {integer(), binary()})" do
      type = Builtins.return_type(Integer, :parse, 1, [Type.binary()])
      assert type.dynamic?
    end
  end

  describe "String" do
    test "String.length/1 returns dynamic(integer())" do
      type = Builtins.return_type(String, :length, 1, [Type.binary()])
      assert %Type{kind: :integer, dynamic?: true} = type
    end

    test "String.upcase/1 returns dynamic(binary())" do
      type = Builtins.return_type(String, :upcase, 1, [Type.binary()])
      assert %Type{kind: :binary, dynamic?: true} = type
    end
  end

  describe "Enum" do
    test "Enum.map/2 returns dynamic(list())" do
      type = Builtins.return_type(Enum, :map, 2, [Type.list(), Type.dynamic()])
      assert %Type{kind: :list, dynamic?: true} = type
    end

    test "Enum.count/1 returns dynamic(integer())" do
      type = Builtins.return_type(Enum, :count, 1, [Type.list()])
      assert %Type{kind: :integer, dynamic?: true} = type
    end

    test "Enum.each/2 returns :ok" do
      type = Builtins.return_type(Enum, :each, 2, [Type.list(), Type.dynamic()])
      assert %Type{kind: :atom, params: :ok} = type
    end
  end

  describe "Map" do
    test "Map.new/0 returns empty_map" do
      type = Builtins.return_type(Map, :new, 0, [])
      assert %Type{kind: :map, params: {[], false}} = type
    end

    test "Map.put/3 returns dynamic(map())" do
      type = Builtins.return_type(Map, :put, 3, [Type.map(), Type.atom(:key), Type.integer()])
      assert %Type{kind: :map, dynamic?: true} = type
    end
  end

  describe "IO" do
    test "IO.puts/1 returns :ok" do
      type = Builtins.return_type(IO, :puts, 1, [Type.binary()])
      assert %Type{kind: :atom, params: :ok} = type
    end

    test "IO.inspect/1 returns the argument type" do
      type = Builtins.return_type(IO, :inspect, 1, [Type.integer()])
      assert %Type{kind: :integer} = type
    end
  end

  describe "fallback" do
    test "unknown module/function returns nil" do
      assert nil == Builtins.return_type(UnknownModule, :unknown_fun, 0, [])
    end
  end
end
