defmodule Typle.Inference.PatternTest do
  use ExUnit.Case, async: true

  alias Typle.Inference.Pattern
  alias Typle.Type

  describe "infer/2" do
    test "binds a simple variable to the matched type" do
      ast = quote(do: x)
      bindings = Pattern.infer(ast, Type.integer())
      assert %{x: %Type{kind: :integer}} = bindings
    end

    test "underscore creates no bindings" do
      ast = quote(do: _)
      assert %{} = Pattern.infer(ast, Type.integer())
    end

    test "pin operator creates no bindings" do
      ast = {:^, [], [{:x, [], nil}]}
      assert %{} = Pattern.infer(ast, Type.integer())
    end

    test "two-element tuple pattern" do
      ast = quote(do: {a, b})
      bindings = Pattern.infer(ast, Type.dynamic())
      assert Map.has_key?(bindings, :a)
      assert Map.has_key?(bindings, :b)
    end

    test "match operator binds both sides" do
      ast = quote(do: x = y)
      bindings = Pattern.infer(ast, Type.integer())
      assert %{x: %Type{kind: :integer}, y: %Type{kind: :integer}} = bindings
    end

    test "list pattern binds elements" do
      ast = quote(do: [a, b, c])
      bindings = Pattern.infer(ast, Type.list(Type.integer()))
      assert Map.has_key?(bindings, :a)
      assert Map.has_key?(bindings, :b)
      assert Map.has_key?(bindings, :c)
    end

    test "literal patterns create no bindings" do
      assert %{} = Pattern.infer(42, Type.integer())
      assert %{} = Pattern.infer(:ok, Type.atom(:ok))
      assert %{} = Pattern.infer("hello", Type.binary())
    end

    test "map pattern extracts value bindings" do
      ast = quote(do: %{name: name})
      bindings = Pattern.infer(ast, Type.map())
      assert Map.has_key?(bindings, :name)
    end
  end
end
