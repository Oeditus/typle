defmodule Typle.BeamTest do
  use ExUnit.Case, async: true

  alias Typle.{Beam, Type}

  describe "read_signatures/1" do
    test "reads signatures from Integer module" do
      assert {:ok, sigs} = Beam.read_signatures(Integer)
      assert is_list(sigs)
      assert length(sigs) > 0

      sig = Enum.find(sigs, &(&1.fun == :to_string and &1.arity == 1))
      assert sig != nil
      assert is_list(sig.clauses)
      assert [{[_arg], _ret}] = sig.clauses
    end

    test "reads signatures from String module" do
      assert {:ok, sigs} = Beam.read_signatures(String)
      assert Enum.any?(sigs, &(&1.fun == :length and &1.arity == 1))
    end

    test "reads signatures from Enum module" do
      assert {:ok, sigs} = Beam.read_signatures(Enum)
      assert Enum.any?(sigs, &(&1.fun == :map and &1.arity == 2))
    end

    test "returns error for non-existent module" do
      assert {:error, _} = Beam.read_signatures(NoSuchModuleEver)
    end
  end

  describe "decode_type/1" do
    test "decodes :term" do
      assert %Type{kind: :term} = Beam.decode_type(:term)
    end

    test "decodes bitmap for integer" do
      assert %Type{kind: :integer} = Beam.decode_type(%{bitmap: 0x08})
    end

    test "decodes bitmap for binary" do
      assert %Type{kind: :binary} = Beam.decode_type(%{bitmap: 0x01})
    end

    test "decodes bitmap for float" do
      assert %Type{kind: :float} = Beam.decode_type(%{bitmap: 0x10})
    end

    test "decodes combined bitmap as union" do
      # integer | float = 0x08 | 0x10 = 0x18 = 24
      result = Beam.decode_type(%{bitmap: 0x18})
      assert %Type{kind: :union} = result
    end

    test "decodes dynamic wrapper" do
      result = Beam.decode_type(%{dynamic: %{bitmap: 0x01}})
      assert %Type{kind: :binary, dynamic?: true} = result
    end

    test "decodes atom union" do
      result = Beam.decode_type(%{atom: {:union, %{ok: [], error: []}}})
      assert %Type{kind: :union} = result
    end

    test "decodes single atom" do
      result = Beam.decode_type(%{atom: {:union, %{ok: []}}})
      assert %Type{kind: :atom, params: :ok} = result
    end

    test "decodes closed tuple" do
      result = Beam.decode_type(%{tuple: {:closed, [%{bitmap: 0x08}, %{bitmap: 0x01}]}})

      assert %Type{kind: :tuple, params: {:closed, [%Type{kind: :integer}, %Type{kind: :binary}]}} =
               result
    end

    test "decodes list type" do
      result = Beam.decode_type(%{list: {:term, :term}})
      assert %Type{kind: :list} = result
    end

    test "decodes open map" do
      result = Beam.decode_type(%{map: {:open, []}})
      assert %Type{kind: :map, params: {[], true}} = result
    end

    test "Integer.to_string/1 signature has correct types" do
      {:ok, sigs} = Beam.read_signatures(Integer)
      sig = Enum.find(sigs, &(&1.fun == :to_string and &1.arity == 1))
      [{[arg_type], ret_type}] = sig.clauses

      assert %Type{kind: :integer} = arg_type
      assert %Type{kind: :binary, dynamic?: true} = ret_type
    end

    test "Integer.parse/1 signature has error | {integer, binary} return" do
      {:ok, sigs} = Beam.read_signatures(Integer)
      sig = Enum.find(sigs, &(&1.fun == :parse and &1.arity == 1))
      [{[_arg_type], ret_type}] = sig.clauses

      assert ret_type.dynamic?
      type_str = Type.to_string(ret_type)
      assert type_str =~ "error"
      assert type_str =~ "integer()"
    end
  end
end
