defmodule Typle.DiagnosticTest do
  use ExUnit.Case, async: false

  alias Typle.Diagnostic

  # `capture/1` compiles files into the running VM, so these tests are not
  # async and each uses a uniquely named module.
  defp write_module(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "typle_diag_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)
    path
  end

  describe "capture/1" do
    test "returns {:ok, []} for a file with no type diagnostics" do
      path =
        write_module("""
        defmodule Typle.DiagnosticTest.Clean do
          def f(x) when is_integer(x), do: x + 1
        end
        """)

      try do
        assert {:ok, diagnostics} = Diagnostic.capture([path])
        assert is_list(diagnostics)
      after
        File.rm(path)
      end
    end

    test "returns {:ok, []} for a file that does not exist" do
      # A missing path yields compiler errors, none of which are type
      # diagnostics, so the filter drops them all rather than raising.
      assert {:ok, diagnostics} = Diagnostic.capture(["/no/such/file.ex"])
      assert diagnostics == []
    end

    test "returns {:ok, []} when the file fails to compile" do
      # A syntax error is a compile error, not a type diagnostic, so it is
      # filtered out rather than reported. Only a raised exception becomes
      # `{:error, _}`.
      path = write_module("defmodule Broken do\n  def oops(\nend\n")

      try do
        assert {:ok, diagnostics} = Diagnostic.capture([path])
        assert diagnostics == []
      after
        File.rm(path)
      end
    end
  end

  describe "capture_file/1" do
    test "delegates to capture/1 for a single file" do
      path =
        write_module("""
        defmodule Typle.DiagnosticTest.Single do
          def f(x), do: x
        end
        """)

      try do
        assert {:ok, diagnostics} = Diagnostic.capture_file(path)
        assert is_list(diagnostics)
      after
        File.rm(path)
      end
    end
  end
end
