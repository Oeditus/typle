defmodule Typle.SignatureStoreTest do
  use ExUnit.Case

  alias Typle.{SignatureStore, Type}

  setup do
    SignatureStore.clear()
    :ok
  end

  describe "init/0" do
    test "creates the ETS table without error" do
      assert :ok = SignatureStore.init()
      assert :ok = SignatureStore.init()
    end
  end

  describe "load_module/1" do
    test "loads signatures from Integer" do
      assert :ok = SignatureStore.load_module(Integer)
      assert {:ok, clauses} = SignatureStore.lookup(Integer, :to_string, 1)
      assert is_list(clauses)
    end

    test "returns error for non-existent module" do
      assert {:error, _} = SignatureStore.load_module(NoSuchModuleEver)
    end
  end

  describe "lookup/3" do
    test "returns :error for unknown function" do
      assert :error = SignatureStore.lookup(Integer, :nonexistent_function, 0)
    end

    test "auto-loads module on first lookup" do
      SignatureStore.clear()
      assert {:ok, _clauses} = SignatureStore.lookup(Integer, :to_string, 1)
    end
  end

  describe "return_type/4" do
    test "returns the return type for Integer.to_string/1" do
      type = SignatureStore.return_type(Integer, :to_string, 1, [Type.integer()])
      assert %Type{kind: :binary, dynamic?: true} = type
    end

    test "returns dynamic for unknown functions" do
      type = SignatureStore.return_type(NoSuchModule, :no_fun, 0, [])
      assert %Type{dynamic?: true} = type
    end
  end

  describe "clear/0" do
    test "removes all cached signatures" do
      SignatureStore.load_module(Integer)
      assert {:ok, _} = SignatureStore.lookup(Integer, :to_string, 1)

      SignatureStore.clear()
      # After clear, it will auto-load again, but the cache was emptied
      assert {:ok, _} = SignatureStore.lookup(Integer, :to_string, 1)
    end
  end
end
