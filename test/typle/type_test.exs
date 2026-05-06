defmodule Typle.TypeTest do
  use ExUnit.Case, async: true

  alias Typle.Type

  doctest Typle.Type

  describe "constructors" do
    test "term/0 creates top type" do
      assert %Type{kind: :term} = Type.term()
    end

    test "none/0 creates bottom type" do
      assert %Type{kind: :none} = Type.none()
    end

    test "integer/0" do
      assert %Type{kind: :integer, dynamic?: false} = Type.integer()
    end

    test "float/0" do
      assert %Type{kind: :float} = Type.float()
    end

    test "binary/0" do
      assert %Type{kind: :binary} = Type.binary()
    end

    test "number/0 creates a union of integer and float" do
      assert %Type{kind: :union, params: types} = Type.number()
      kinds = Enum.map(types, & &1.kind) |> Enum.sort()
      assert [:float, :integer] = kinds
    end

    test "atom/0 creates generic atom" do
      assert %Type{kind: :atom, params: nil} = Type.atom()
    end

    test "atom/1 with literal" do
      assert %Type{kind: :atom, params: :ok} = Type.atom(:ok)
      assert %Type{kind: :atom, params: true} = Type.atom(true)
    end

    test "boolean/0 is union of true and false atoms" do
      assert %Type{
               kind: :union,
               params: [%Type{kind: :atom, params: true}, %Type{kind: :atom, params: false}]
             } =
               Type.boolean()
    end

    test "tuple/1 creates closed tuple" do
      t = Type.tuple([Type.integer(), Type.binary()])

      assert %Type{kind: :tuple, params: {:closed, [%Type{kind: :integer}, %Type{kind: :binary}]}} =
               t
    end

    test "open_tuple/1 creates open tuple" do
      t = Type.open_tuple([Type.atom()])
      assert %Type{kind: :tuple, params: {:open, [%Type{kind: :atom}]}} = t
    end

    test "list/0 and list/1" do
      assert %Type{kind: :list, params: %Type{kind: :term}} = Type.list()
      assert %Type{kind: :list, params: %Type{kind: :integer}} = Type.list(Type.integer())
    end

    test "empty_list/0" do
      assert %Type{kind: :empty_list} = Type.empty_list()
    end

    test "map/0 creates open map" do
      assert %Type{kind: :map, params: {[], true}} = Type.map()
    end

    test "map/2 with keys" do
      t = Type.map([name: Type.binary()], false)
      assert %Type{kind: :map, params: {[name: %Type{kind: :binary}], false}} = t
    end

    test "function/1" do
      t = Type.function([{[Type.integer()], Type.binary()}])
      assert %Type{kind: :function, params: [{[%Type{kind: :integer}], %Type{kind: :binary}}]} = t
    end

    test "dynamic/0 wraps term in dynamic" do
      assert %Type{kind: :term, dynamic?: true} = Type.dynamic()
    end

    test "dynamic/1 wraps inner type" do
      assert %Type{kind: :integer, dynamic?: true} = Type.dynamic(Type.integer())
    end

    test "pid/0, port/0, reference/0" do
      assert %Type{kind: :pid} = Type.pid()
      assert %Type{kind: :port} = Type.port()
      assert %Type{kind: :reference} = Type.reference()
    end
  end

  describe "union/1" do
    test "single-element union returns the element" do
      assert %Type{kind: :integer} = Type.union([Type.integer()])
    end

    test "multi-element union" do
      t = Type.union([Type.integer(), Type.binary()])
      assert %Type{kind: :union, params: [_, _]} = t
    end

    test "flattens nested unions" do
      inner = Type.union([Type.integer(), Type.float()])
      outer = Type.union([inner, Type.binary()])
      assert %Type{kind: :union, params: types} = outer
      assert [_, _, _] = types
    end

    test "deduplicates types" do
      t = Type.union([Type.integer(), Type.integer(), Type.binary()])
      assert %Type{kind: :union, params: types} = t
      assert [_, _] = types
    end
  end

  describe "intersection/1 and negation/1" do
    test "single-element intersection returns the element" do
      assert %Type{kind: :integer} = Type.intersection([Type.integer()])
    end

    test "negation wraps" do
      t = Type.negation(Type.atom(nil))
      assert %Type{kind: :negation, params: %Type{kind: :atom, params: nil}} = t
    end
  end

  describe "predicates" do
    test "term?/1" do
      assert Type.term?(Type.term())
      refute Type.term?(Type.integer())
    end

    test "none?/1" do
      assert Type.none?(Type.none())
      refute Type.none?(Type.term())
    end
  end

  describe "to_string/1" do
    test "basic types" do
      assert Type.to_string(Type.integer()) == "integer()"
      assert Type.to_string(Type.float()) == "float()"
      assert Type.to_string(Type.binary()) == "binary()"
      assert Type.to_string(Type.bitstring()) == "bitstring()"
      assert Type.to_string(Type.pid()) == "pid()"
      assert Type.to_string(Type.port()) == "port()"
      assert Type.to_string(Type.reference()) == "reference()"
      assert Type.to_string(Type.term()) == "term()"
      assert Type.to_string(Type.none()) == "none()"
      assert Type.to_string(Type.empty_list()) == "empty_list()"
    end

    test "atoms" do
      assert Type.to_string(Type.atom()) == "atom()"
      assert Type.to_string(Type.atom(:ok)) == ":ok"
      assert Type.to_string(Type.atom(true)) == "true"
      assert Type.to_string(Type.atom(false)) == "false"
    end

    test "dynamic" do
      assert Type.to_string(Type.dynamic()) == "dynamic()"
      assert Type.to_string(Type.dynamic(Type.integer())) == "dynamic(integer())"
      assert Type.to_string(Type.dynamic(Type.binary())) == "dynamic(binary())"
    end

    test "tuple" do
      t = Type.tuple([Type.atom(:ok), Type.integer()])
      assert Type.to_string(t) == "{:ok, integer()}"
    end

    test "open tuple" do
      t = Type.open_tuple([Type.integer()])
      assert Type.to_string(t) == "{integer(), ...}"
    end

    test "list" do
      assert Type.to_string(Type.list(Type.integer())) == "list(integer())"
      assert Type.to_string(Type.list()) == "list(term())"
    end

    test "map" do
      assert Type.to_string(Type.map()) == "map()"
      assert Type.to_string(Type.map([], false)) == "empty_map()"
      assert Type.to_string(Type.map([name: Type.binary()], true)) == "%{..., name: binary()}"

      assert Type.to_string(Type.map([name: Type.binary()], false)) == "%{name: binary()}"
    end

    test "function" do
      t = Type.function([{[Type.integer()], Type.binary()}])
      assert Type.to_string(t) == "(integer() -> binary())"
    end

    test "union" do
      t = Type.union([Type.atom(:ok), Type.atom(:error)])
      assert Type.to_string(t) == ":error or :ok"
    end

    test "intersection" do
      t = Type.intersection([Type.atom(), Type.integer()])
      assert Type.to_string(t) == "atom() and integer()"
    end

    test "negation" do
      t = Type.negation(Type.atom(:error))
      assert Type.to_string(t) == "not :error"
    end
  end

  describe "Inspect protocol" do
    test "renders with #Typle.Type<...> sigil" do
      assert inspect(Type.integer()) == "#Typle.Type<integer()>"
    end
  end

  describe "String.Chars protocol" do
    test "renders type notation" do
      assert "#{Type.binary()}" == "binary()"
    end
  end
end
