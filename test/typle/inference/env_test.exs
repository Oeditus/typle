defmodule Typle.Inference.EnvTest do
  use ExUnit.Case, async: true

  alias Typle.Inference.Env
  alias Typle.Type

  describe "new/1" do
    test "creates an empty environment" do
      env = Env.new()
      assert env.scopes == [%{}]
      assert env.types == %{}
    end

    test "accepts module and file options" do
      env = Env.new(module: MyModule, file: "test.ex")
      assert env.module == MyModule
      assert env.file == "test.ex"
    end
  end

  describe "put_var/3 and get_var/2" do
    test "stores and retrieves a variable type" do
      env = Env.new() |> Env.put_var(:x, Type.integer())
      assert %Type{kind: :integer} = Env.get_var(env, :x)
    end

    test "returns dynamic for unknown variables" do
      env = Env.new()
      assert %Type{dynamic?: true} = Env.get_var(env, :unknown)
    end
  end

  describe "scope management" do
    test "push_scope/1 creates new scope" do
      env = Env.new() |> Env.put_var(:x, Type.integer()) |> Env.push_scope()
      # x is still visible from outer scope
      assert %Type{kind: :integer} = Env.get_var(env, :x)
    end

    test "inner scope shadows outer" do
      env =
        Env.new()
        |> Env.put_var(:x, Type.integer())
        |> Env.push_scope()
        |> Env.put_var(:x, Type.binary())

      assert %Type{kind: :binary} = Env.get_var(env, :x)
    end

    test "pop_scope/1 restores outer scope" do
      env =
        Env.new()
        |> Env.put_var(:x, Type.integer())
        |> Env.push_scope()
        |> Env.put_var(:x, Type.binary())
        |> Env.pop_scope()

      assert %Type{kind: :integer} = Env.get_var(env, :x)
    end

    test "push_scope/2 initializes with bindings" do
      env = Env.new() |> Env.push_scope(%{y: Type.float()})
      assert %Type{kind: :float} = Env.get_var(env, :y)
    end
  end

  describe "record_type/4 and type_at/3" do
    test "records and retrieves expression types by position" do
      env = Env.new() |> Env.record_type(10, 5, Type.integer())
      assert %Type{kind: :integer} = Env.type_at(env, 10, 5)
    end

    test "returns nil for unrecorded positions" do
      env = Env.new()
      assert nil == Env.type_at(env, 1, 1)
    end
  end

  describe "merge_branches/2" do
    test "unions types from multiple branches" do
      env = Env.new()
      branches = [%{x: Type.integer()}, %{x: Type.binary()}]
      env = Env.merge_branches(env, branches)
      type = Env.get_var(env, :x)
      assert %Type{kind: :union} = type
    end

    test "handles variables present in only some branches" do
      env = Env.new()
      branches = [%{x: Type.integer()}, %{y: Type.binary()}]
      env = Env.merge_branches(env, branches)
      assert %Type{kind: :integer} = Env.get_var(env, :x)
      assert %Type{kind: :binary} = Env.get_var(env, :y)
    end
  end
end
