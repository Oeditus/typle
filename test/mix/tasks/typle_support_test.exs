defmodule Mix.Tasks.TypleSupportTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Typle.Support

  describe "parse_location/1" do
    test "parses file:line" do
      assert {:ok, "lib/a.ex", 15} = Support.parse_location("lib/a.ex:15")
    end

    test "parses file:line:col" do
      assert {:ok, "lib/a.ex", 15, 5} = Support.parse_location("lib/a.ex:15:5")
    end

    test "rejects a non-numeric line" do
      assert :error = Support.parse_location("lib/a.ex:abc")
    end

    test "rejects a bare path" do
      assert :error = Support.parse_location("lib/a.ex")
    end

    test "rejects trailing garbage after the line number" do
      assert :error = Support.parse_location("lib/a.ex:15x")
    end
  end

  describe "parse_options/1" do
    test "defaults to text and stable" do
      assert {"text", false} = Support.parse_options([])
    end

    test "accepts json" do
      assert {"json", false} = Support.parse_options(format: "json")
    end

    test "accepts --unstable" do
      assert {"text", true} = Support.parse_options(unstable: true)
    end

    test "raises on an unknown format, naming the valid ones" do
      # Regression: an unrecognised format used to fall through to a
      # FunctionClauseError in output_result/5.
      error = assert_raise Mix.Error, fn -> Support.parse_options(format: "yaml") end
      assert error.message =~ "yaml"
      assert error.message =~ "text"
      assert error.message =~ "json"
    end
  end

  describe "describe/2" do
    test "names the file for :enoent" do
      assert Support.describe(:enoent, file: "lib/a.ex") == "No such file: lib/a.ex"
    end

    test "suggests dump for :no_type_at_position" do
      message = Support.describe(:no_type_at_position, file: "lib/a.ex", line: 3, col: 4)
      assert message =~ "lib/a.ex:3:4"
      assert message =~ "mix typle.dump"
    end

    test "suggests mix compile for an unavailable module" do
      message = Support.describe({:module_not_available, Foo}, [])
      assert message =~ "Foo"
      assert message =~ "mix compile"
    end

    test "names the unsupported checker version and the supported set" do
      message = Support.describe({:unsupported_checker_version, :elixir_checker_v9}, [])
      assert message =~ "elixir_checker_v9"
      assert message =~ "v7, v8"
    end

    test "falls back to inspecting an unknown reason" do
      assert Support.describe(:something_odd, []) =~ "something_odd"
    end
  end
end
