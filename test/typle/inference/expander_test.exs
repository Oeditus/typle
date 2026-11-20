defmodule Typle.Inference.ExpanderTest do
  use ExUnit.Case

  alias Typle.Inference.Expander

  defmodule StderrProbe do
    @moduledoc false

    defmacro __using__(_opts) do
      IO.warn("expansion diagnostic")
      inspect(Process.whereis(:standard_error))
    end
  end

  describe "expand_file/1" do
    test "returns {:ok, ast} for a valid file" do
      path = Path.expand("../../support/sample_module.ex", __DIR__)
      assert {:ok, ast} = Expander.expand_file(path)
      assert is_tuple(ast)
    end

    test "returns {:error, _} for a non-existent file" do
      assert {:error, _} = Expander.expand_file("/no/such/file.ex")
    end

    @tag :tmp_dir
    test "does not replace stderr during expansion", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "stderr_probe.ex")

      File.write!(path, """
      defmodule StderrSample do
        def probe do
          use #{inspect(StderrProbe)}
        end
      end
      """)

      original = Process.whereis(:standard_error)
      assert is_pid(original)
      assert {:ok, ast} = Expander.expand_file(path)
      assert Macro.to_string(ast) =~ inspect(original)
      assert Process.whereis(:standard_error) == original
    end

    test "supports concurrent file expansion and inference" do
      path = Path.expand("../../support/sample_module.ex", __DIR__)
      original = Process.whereis(:standard_error)
      assert {:ok, expected_ast} = Expander.expand_file(path)
      assert {:ok, expected_inference} = Typle.Inference.infer_file(path)

      1..32
      |> Task.async_stream(
        fn _ ->
          assert Process.whereis(:standard_error) == original
          assert {:ok, ^expected_ast} = Expander.expand_file(path)
          assert {:ok, ^expected_inference} = Typle.Inference.infer_file(path)
          assert Process.whereis(:standard_error) == original
        end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.each(fn result -> assert {:ok, true} = result end)

      assert Process.whereis(:standard_error) == original
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

    test "suppresses diagnostics inside the expansion task" do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          original = Process.whereis(:standard_error)
          ast = quote do: use(unquote(StderrProbe))
          expanded = Expander.expand_node(ast)
          assert Macro.to_string(expanded) =~ inspect(original)
          assert Process.whereis(:standard_error) == original
        end)

      assert output == ""
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
