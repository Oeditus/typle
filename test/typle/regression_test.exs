defmodule Typle.RegressionTest do
  use ExUnit.Case

  alias Typle.Inference

  @fixture Path.expand("../support/struct_update_module.ex", __DIR__)

  # A fixture written per-test into a temp dir, so each case isolates the one
  # construct under test rather than sharing a grab-bag file.
  defp infer_source(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "typle_regression_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)

    try do
      Inference.infer_file(path)
    after
      File.rm(path)
    end
  end

  # Branch types are folded into a union at the construct's position, so the
  # atom is not necessarily recorded as a standalone entry.
  defp contains_atom?(type_map, atom) do
    Enum.any?(type_map, fn {_pos, type} -> atom_in?(type, atom) end)
  end

  defp atom_in?(%Typle.Type{kind: :atom, params: atom}, atom), do: true

  defp atom_in?(%Typle.Type{kind: :union, params: types}, atom),
    do: Enum.any?(types, &atom_in?(&1, atom))

  defp atom_in?(_type, _atom), do: false

  describe "a construct inference cannot handle" do
    test "does not abort the rest of the file" do
      # Regression: an empty `case` expands to `{:__block__, _, []}`, which the
      # clause reducer in Expr.infer/2 could not enumerate, raising
      # Protocol.UndefinedError. infer_file/2 had no rescue, so one such
      # construct returned zero types for the entire file.
      {:ok, %{types: types}} =
        infer_source("""
        defmodule Typle.Regression.EmptyCase do
          def before(x), do: x + 1

          def broken(x) do
            case x do
            end
          end

          def after_it(y), do: y
        end
        """)

      lines = types |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

      assert 2 in lines, "expected the function before the bad one to be inferred"
      assert 9 in lines, "expected the function after the bad one to be inferred"
    end
  end

  describe "anonymous functions" do
    test "infers the body and records the parameter" do
      # Regression: the `fn` clause ignored its clauses entirely and returned a
      # zero-arity function type, so the body was never walked.
      {:ok, %{types: types, exprs: exprs}} =
        infer_source("""
        defmodule Typle.Regression.Fn do
          def f(list) do
            Enum.map(list, fn item -> item + 1 end)
          end
        end
        """)

      fn_types = for {_pos, %Typle.Type{kind: :function} = t} <- types, do: t
      assert [%Typle.Type{params: [{[_arg], ret}]}] = fn_types
      assert ret.kind == :union
      assert Enum.any?(Map.values(exprs), &(&1 == "item"))
    end
  end

  describe "with/else and try/rescue" do
    test "records the else branch" do
      # Regression: only `:do` was read, so error branches were invisible.
      {:ok, %{types: types}} =
        infer_source("""
        defmodule Typle.Regression.WithElse do
          def f(x) do
            with {:ok, a} <- x do
              a
            else
              _ -> :boom
            end
          end
        end
        """)

      assert contains_atom?(types, :boom)
    end

    test "records the rescue branch" do
      {:ok, %{types: types}} =
        infer_source("""
        defmodule Typle.Regression.TryRescue do
          def f(x) do
            try do
              x
            rescue
              _ -> :rescued
            end
          end
        end
        """)

      assert contains_atom?(types, :rescued)
    end
  end

  describe "calls to sibling functions" do
    test "resolve a defp defined later in the file" do
      # Regression: local calls consulted only the compiled beam, which does not
      # exist for a file under analysis, so every sibling call was dynamic().
      {:ok, %{types: types}} =
        infer_source("""
        defmodule Typle.Regression.Sibling do
          def a(x), do: b(x)
          defp b(y), do: y + 1
        end
        """)

      # {2, 17} is the `b(x)` call site.
      assert %Typle.Type{} = type = Map.get(types, {2, 17})
      refute Typle.Type.term?(type), "expected b/1's inferred return type, got dynamic()"
    end
  end

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
