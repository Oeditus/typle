defmodule Typle.Unstable.TypeCaptureTest do
  use ExUnit.Case, async: false

  alias Typle.Unstable.TypeCapture

  # The capture table is a named ETS table, so these tests share global state
  # and must not run concurrently.
  setup do
    TypeCapture.init()
    :ok
  end

  describe "init/0" do
    test "creates the table and is idempotent" do
      assert :ok = TypeCapture.init()
      assert :ok = TypeCapture.init()
    end

    test "clears previously captured entries" do
      TypeCapture.record(1, 1, :something)
      assert %{{1, 1} => :something} = TypeCapture.all()

      TypeCapture.init()
      assert TypeCapture.all() == %{}
    end
  end

  describe "record/3 and all/0" do
    test "records and returns a single entry" do
      TypeCapture.record(10, 5, :integer)
      assert TypeCapture.all() == %{{10, 5} => :integer}
    end

    test "accumulates multiple entries" do
      TypeCapture.record(1, 1, :a)
      TypeCapture.record(2, 2, :b)

      assert TypeCapture.all() == %{{1, 1} => :a, {2, 2} => :b}
    end

    test "a later record at the same position overwrites" do
      TypeCapture.record(1, 1, :first)
      TypeCapture.record(1, 1, :second)

      assert TypeCapture.all() == %{{1, 1} => :second}
    end
  end

  describe "get/2" do
    test "returns {:ok, value} for a recorded position" do
      TypeCapture.record(3, 4, :binary)
      assert {:ok, :binary} = TypeCapture.get(3, 4)
    end

    test "returns :error for an unrecorded position" do
      assert :error = TypeCapture.get(99, 99)
    end
  end
end
