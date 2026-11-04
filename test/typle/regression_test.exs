defmodule Typle.RegressionTest do
  use ExUnit.Case

  alias Typle.Inference

  @fixture Path.expand("../support/struct_update_module.ex", __DIR__)

  describe "struct update syntax (%{struct | key: value})" do
    test "does not crash inference" do
      # Regression: the AST is `{:%{}, _, [{:|, _, [struct, [key: value]]}]}`, so
      # the map-literal clause received a bare `:|` tuple where it expected
      # `{key, value}` pairs and raised FunctionClauseError. Struct updates are
      # ubiquitous in real Elixir, so this took down whole files.
      assert {:ok, %{types: types}} = Inference.infer_file(@fixture)
      assert is_map(types)
      assert map_size(types) > 0
    end

    test "records the struct being updated" do
      assert {:ok, %{exprs: exprs}} = Inference.infer_file(@fixture)

      assert Enum.any?(Map.values(exprs), &(&1 =~ "data")),
             "expected the updated struct to appear in the expression map"
    end
  end

  describe "with expressions" do
    test "inline `with ..., do: x` expands to valid AST" do
      # Regression: the expander spliced the body keyword list into the clause
      # list, producing `with x <- y, {:do, z}` -- AST that Macro.to_string/1
      # cannot even print.
      source = "with {:ok, a} <- x, do: a"
      {:ok, ast} = Code.string_to_quoted(source, columns: true)

      assert {:ok, expanded} = ExPanda.expand(ast)
      assert is_binary(Macro.to_string(expanded))
      assert Macro.to_string(expanded) =~ "with"
    end

    test "block `with` expands to valid AST" do
      source = """
      with {:ok, a} <- x do
        a
      end
      """

      {:ok, ast} = Code.string_to_quoted(source, columns: true)
      assert {:ok, expanded} = ExPanda.expand(ast)
      assert is_binary(Macro.to_string(expanded))
    end

    test "`with` with an else branch expands to valid AST" do
      source = """
      with {:ok, a} <- x do
        a
      else
        _ -> :error
      end
      """

      {:ok, ast} = Code.string_to_quoted(source, columns: true)
      assert {:ok, expanded} = ExPanda.expand(ast)
      assert is_binary(Macro.to_string(expanded))
    end
  end

  describe "for comprehensions" do
    test "expands to valid AST" do
      # Regression: same body-splicing bug as `with`.
      source = "for {_k, v} <- list, v > 0, do: v * 2"
      {:ok, ast} = Code.string_to_quoted(source, columns: true)

      assert {:ok, expanded} = ExPanda.expand(ast)
      assert is_binary(Macro.to_string(expanded))
    end

    test "with :into expands to valid AST" do
      source = "for v <- list, into: %{}, do: {v, v}"
      {:ok, ast} = Code.string_to_quoted(source, columns: true)

      assert {:ok, expanded} = ExPanda.expand(ast)
      assert is_binary(Macro.to_string(expanded))
    end
  end

  describe "ExCk chunk versions" do
    test "reads signatures from compiler output (v7 or v8)" do
      # Regression: only :elixir_checker_v7 was accepted, so every read failed
      # with {:unsupported_checker_version, :elixir_checker_v8} on Elixir
      # 1.20.4+. v8 also stores `exports` as a list rather than a map.
      assert {:ok, sigs} = Typle.Beam.read_signatures(Integer)
      assert [_ | _] = sigs
      assert Enum.any?(sigs, &(&1.fun == :to_string and &1.arity == 1))
    end

    test "decoded signatures carry clauses and types" do
      {:ok, sigs} = Typle.Beam.read_signatures(Integer)
      sig = Enum.find(sigs, &(&1.fun == :to_string and &1.arity == 1))

      assert [_ | _] = sig.clauses
      assert Enum.all?(sig.clauses, fn {args, ret} -> is_list(args) and ret != nil end)
    end
  end
end
