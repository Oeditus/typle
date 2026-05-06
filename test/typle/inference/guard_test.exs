defmodule Typle.Inference.GuardTest do
  use ExUnit.Case, async: true

  alias Typle.Inference.Guard
  alias Typle.Type

  describe "refine/1" do
    test "is_integer(x) refines x to integer" do
      ast = quote(do: is_integer(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :integer}} = refs
    end

    test "is_binary(x) refines x to binary" do
      ast = quote(do: is_binary(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :binary}} = refs
    end

    test "is_atom(x) refines x to atom" do
      ast = quote(do: is_atom(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :atom}} = refs
    end

    test "is_list(x) refines x to list" do
      ast = quote(do: is_list(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :list}} = refs
    end

    test "is_map(x) refines x to map" do
      ast = quote(do: is_map(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :map}} = refs
    end

    test "is_nil(x) refines x to nil atom" do
      ast = quote(do: is_nil(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :atom, params: nil}} = refs
    end

    test "is_number(x) refines x to number (integer or float)" do
      ast = quote(do: is_number(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :union}} = refs
    end

    test "compound and refines both" do
      ast = quote(do: is_integer(x) and is_binary(y))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :integer}, y: %Type{kind: :binary}} = refs
    end

    test "compound or unions types" do
      ast = quote(do: is_integer(x) or is_float(x))
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :union}} = refs
    end

    test "comparison refines to number" do
      ast = quote(do: x > 0)
      refs = Guard.refine(ast)
      assert %{x: %Type{kind: :union}} = refs
    end

    test "unknown guard returns empty refinements" do
      ast = quote(do: some_custom_guard(x))
      refs = Guard.refine(ast)
      assert refs == %{}
    end
  end
end
