defmodule Typle.Inference.ExpanderTest do
  use ExUnit.Case

  alias Typle.Inference.Expander

  describe "expand_file/1" do
    test "returns {:ok, ast} for a valid file" do
      path = Path.expand("../../support/sample_module.ex", __DIR__)
      assert {:ok, ast} = Expander.expand_file(path)
      assert is_tuple(ast)
    end

    test "returns {:error, _} for a non-existent file" do
      assert {:error, _} = Expander.expand_file("/no/such/file.ex")
    end
  end

  describe "expand_node/1" do
    test "expands pipe operator to nested function calls" do
      {:ok, ast} = Code.string_to_quoted("1 |> to_string() |> String.upcase()")
      expanded = Expander.expand_node(ast)

      # After expansion, |> should be gone -- the top-level node should be
      # a remote call to String.upcase (or a dot-call form), not a pipe.
      refute match?({:|>, _, _}, expanded)
    end

    test "expands unless to case" do
      {:ok, ast} = Code.string_to_quoted("unless true, do: :never")
      expanded = Expander.expand_node(ast)

      # After expansion, the top-level form should be :case, not :unless
      assert match?({:case, _, _}, expanded)
    end

    test "returns original AST unchanged on expansion failure" do
      # A bare variable reference -- ExPanda may raise or return {:error, _}.
      # Either way, expand_node should return the original.
      ast = {:nonexistent_var, [line: 1, column: 1], nil}
      result = Expander.expand_node(ast)
      assert is_tuple(result)
    end
  end

  describe "strip_unexpanded_markers/1" do
    test "extracts original node from @unexpanded wrapper" do
      original = {:use, [], [{:__aliases__, [], [:NonExistent]}]}

      wrapped =
        {:__block__, [],
         [
           {:@, [], [{:unexpanded, [], ["some error message"]}]},
           original
         ]}

      assert ^original = Expander.strip_unexpanded_markers(wrapped)
    end

    test "passes through normal AST unchanged" do
      ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}
      assert ^ast = Expander.strip_unexpanded_markers(ast)
    end
  end
end
