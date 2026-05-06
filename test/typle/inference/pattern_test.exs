defmodule Typle.Inference.PatternTest do
  use ExUnit.Case, async: true

  alias Typle.Inference.Pattern
  alias Typle.Type

  describe "infer/2 basic bindings" do
    test "binds a simple variable to the matched type" do
      ast = quote(do: x)
      {bindings, _positions} = Pattern.infer(ast, Type.integer())
      assert %{x: %Type{kind: :integer}} = bindings
    end

    test "underscore creates no bindings" do
      ast = quote(do: _)
      {bindings, _positions} = Pattern.infer(ast, Type.integer())
      assert bindings == %{}
    end

    test "pin operator creates no bindings" do
      ast = {:^, [], [{:x, [], nil}]}
      {bindings, _positions} = Pattern.infer(ast, Type.integer())
      assert bindings == %{}
    end

    test "two-element tuple pattern" do
      ast = quote(do: {a, b})
      {bindings, _positions} = Pattern.infer(ast, Type.dynamic())
      assert Map.has_key?(bindings, :a)
      assert Map.has_key?(bindings, :b)
    end

    test "match operator binds both sides" do
      ast = quote(do: x = y)
      {bindings, _positions} = Pattern.infer(ast, Type.integer())
      assert %{x: %Type{kind: :integer}, y: %Type{kind: :integer}} = bindings
    end

    test "list pattern binds elements" do
      ast = quote(do: [a, b, c])
      {bindings, _positions} = Pattern.infer(ast, Type.list(Type.integer()))
      assert Map.has_key?(bindings, :a)
      assert Map.has_key?(bindings, :b)
      assert Map.has_key?(bindings, :c)
    end

    test "literal patterns create no bindings" do
      {bindings1, _} = Pattern.infer(42, Type.integer())
      {bindings2, _} = Pattern.infer(:ok, Type.atom(:ok))
      {bindings3, _} = Pattern.infer("hello", Type.binary())
      assert bindings1 == %{}
      assert bindings2 == %{}
      assert bindings3 == %{}
    end

    test "map pattern extracts value bindings" do
      ast = quote(do: %{name: name})
      {bindings, _positions} = Pattern.infer(ast, Type.map())
      assert Map.has_key?(bindings, :name)
    end
  end

  describe "type decomposition" do
    test "two-element tuple decomposes into element types" do
      tuple_type = Type.tuple([Type.integer(), Type.binary()])
      ast = quote(do: {a, b})
      {bindings, _} = Pattern.infer(ast, tuple_type)
      assert %{a: %Type{kind: :integer}, b: %Type{kind: :binary}} = bindings
    end

    test "N-element tuple decomposes into element types" do
      tuple_type = Type.tuple([Type.atom(:ok), Type.integer(), Type.binary()])
      ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]}
      {bindings, _} = Pattern.infer(ast, tuple_type)

      assert %{a: %Type{kind: :atom}, b: %Type{kind: :integer}, c: %Type{kind: :binary}} =
               bindings
    end

    test "union is narrowed to matching tuple shape" do
      # {integer(), binary()} or :error -- narrowed to {integer(), binary()} for a 2-tuple pattern
      union_type =
        Type.union([
          Type.tuple([Type.integer(), Type.binary()]),
          Type.atom(:error)
        ])

      ast = quote(do: {num, rest})
      {bindings, _} = Pattern.infer(ast, union_type)
      assert %{num: %Type{kind: :integer}, rest: %Type{kind: :binary}} = bindings
    end

    test "dynamic wrapper is preserved on decomposed elements" do
      dynamic_tuple = Type.dynamic(Type.tuple([Type.integer(), Type.binary()]))
      ast = quote(do: {a, b})
      {bindings, _} = Pattern.infer(ast, dynamic_tuple)

      assert %{a: %Type{kind: :integer, dynamic?: true}, b: %Type{kind: :binary, dynamic?: true}} =
               bindings
    end

    test "dynamic union is narrowed and elements stay dynamic" do
      # This is exactly what Integer.parse/1 returns:
      # dynamic({integer(), binary()} or :error)
      parse_type =
        Type.dynamic(
          Type.union([
            Type.tuple([Type.integer(), Type.binary()]),
            Type.atom(:error)
          ])
        )

      ast = quote(do: {num, rest})
      {bindings, _} = Pattern.infer(ast, parse_type)
      assert %{num: %Type{kind: :integer, dynamic?: true}} = bindings
      assert %{rest: %Type{kind: :binary, dynamic?: true}} = bindings
    end

    test "list pattern decomposes element types" do
      list_type = Type.list(Type.integer())
      ast = quote(do: [a, b, c])
      {bindings, _} = Pattern.infer(ast, list_type)

      assert %{a: %Type{kind: :integer}, b: %Type{kind: :integer}, c: %Type{kind: :integer}} =
               bindings
    end

    test "head|tail pattern decomposes list types" do
      list_type = Type.list(Type.binary())
      ast = quote(do: [h | t])
      {bindings, _} = Pattern.infer(ast, list_type)
      assert %{h: %Type{kind: :binary}} = bindings
      assert %{t: %Type{kind: :list, params: %Type{kind: :binary}}} = bindings
    end

    test "map pattern extracts known field types" do
      map_type = Type.map([{:name, Type.binary()}, {:age, Type.integer()}], false)
      ast = quote(do: %{name: n, age: a})
      {bindings, _} = Pattern.infer(ast, map_type)
      assert %{n: %Type{kind: :binary}, a: %Type{kind: :integer}} = bindings
    end

    test "non-matching tuple arity falls back to dynamic" do
      # 3-tuple type matched against a 2-tuple pattern
      tuple_type = Type.tuple([Type.integer(), Type.binary(), Type.atom()])
      ast = quote(do: {a, b})
      {bindings, _} = Pattern.infer(ast, tuple_type)
      assert %{a: %Type{dynamic?: true}, b: %Type{dynamic?: true}} = bindings
    end

    test "nested tuple decomposition" do
      # {:ok, {integer(), binary()}}
      inner = Type.tuple([Type.integer(), Type.binary()])
      outer = Type.tuple([Type.atom(:ok), inner])
      ast = quote(do: {:ok, {num, rest}})
      {bindings, _} = Pattern.infer(ast, outer)
      assert %{num: %Type{kind: :integer}, rest: %Type{kind: :binary}} = bindings
    end

    test "union of tuples with different first-element literals" do
      # {:ok, integer()} or {:error, binary()}
      union_type =
        Type.union([
          Type.tuple([Type.atom(:ok), Type.integer()]),
          Type.tuple([Type.atom(:error), Type.binary()])
        ])

      # Both are 2-tuples, so both match -- variable gets union of element types
      ast = quote(do: {tag, val})
      {bindings, _} = Pattern.infer(ast, union_type)

      assert %Type{kind: :union} = bindings[:tag]
      assert %Type{kind: :union} = bindings[:val]
    end
  end

  describe "position recording" do
    test "records variable positions in pattern" do
      ast = {:x, [line: 5, column: 3], nil}
      {_bindings, positions} = Pattern.infer(ast, Type.integer())
      assert %{{5, 3} => %Type{kind: :integer}} = positions
    end

    test "records multiple variable positions in tuple pattern" do
      left = {:a, [line: 10, column: 2], nil}
      right = {:b, [line: 10, column: 5], nil}
      ast = {left, right}
      tuple_type = Type.tuple([Type.integer(), Type.binary()])
      {_bindings, positions} = Pattern.infer(ast, tuple_type)
      assert %{{10, 2} => %Type{kind: :integer}} = positions
      assert %{{10, 5} => %Type{kind: :binary}} = positions
    end

    test "does not record positions without line metadata" do
      ast = {:x, [], nil}
      {_bindings, positions} = Pattern.infer(ast, Type.integer())
      assert positions == %{}
    end
  end
end
