defmodule Typle.Beam do
  @moduledoc """
  Reads inferred type signatures from compiled `.beam` files.

  The Elixir 1.20 compiler stores function signatures in the "ExCk" chunk
  using an internal representation tagged `:elixir_checker_v7`. This module
  decodes that representation into `Typle.Type` structs.
  """

  alias Typle.Type

  @type signature :: %{
          fun: atom(),
          arity: non_neg_integer(),
          clauses: [{[Type.t()], Type.t()}]
        }

  @supported_versions [:elixir_checker_v7]

  # Bitmap flags -- reverse-engineered from elixir_checker_v7 representations.
  # Each bit encodes a "simple" type that has no further internal structure.
  @bitmap_binary 0x01
  @bitmap_bitstring 0x02
  @bitmap_empty_list 0x04
  @bitmap_integer 0x08
  @bitmap_float 0x10
  @bitmap_pid 0x20
  @bitmap_port 0x40
  @bitmap_reference 0x80

  @bitmap_types [
    {@bitmap_binary, :binary},
    {@bitmap_bitstring, :bitstring},
    {@bitmap_empty_list, :empty_list},
    {@bitmap_integer, :integer},
    {@bitmap_float, :float},
    {@bitmap_pid, :pid},
    {@bitmap_port, :port},
    {@bitmap_reference, :reference}
  ]

  @doc """
  Reads all exported function signatures from a compiled module.

  Accepts a module atom (looked up via `:code.which/1`) or a path to a `.beam` file.

  ## Examples

      iex> {:ok, sigs} = Typle.Beam.read_signatures(Integer)
      iex> Enum.find(sigs, & &1.fun == :to_string and &1.arity == 1)
      %{fun: :to_string, arity: 1, clauses: [{[_], _}]}

  """
  @spec read_signatures(module() | String.t()) :: {:ok, [signature()]} | {:error, term()}
  def read_signatures(module_or_path) do
    with {:ok, beam_binary} <- load_beam(module_or_path),
         {:ok, exck_data} <- read_exck_chunk(beam_binary),
         {:ok, exports} <- decode_exck(exck_data) do
      signatures =
        Enum.map(exports, fn {{fun, arity}, %{sig: sig}} ->
          clauses = decode_signature(sig)
          %{fun: fun, arity: arity, clauses: clauses}
        end)

      {:ok, signatures}
    end
  end

  @doc """
  Decodes an internal type representation from the ExCk chunk into a `Typle.Type`.
  """
  @spec decode_type(term()) :: Type.t()
  def decode_type(:term), do: Type.term()

  def decode_type(%{dynamic: inner}) do
    Type.dynamic(decode_type(inner))
  end

  def decode_type(%{} = map) when not is_struct(map) do
    types = decode_type_map(map)

    case types do
      [single] -> single
      many -> Type.union(many)
    end
  end

  def decode_type(other) do
    # Unknown representation -- fall back to term
    _ = other
    Type.term()
  end

  # -- Private: BEAM loading -------------------------------------------------

  defp load_beam(module) when is_atom(module) do
    case :code.which(module) do
      path when is_list(path) -> {:ok, path}
      _ -> {:error, {:module_not_found, module}}
    end
  end

  defp load_beam(path) when is_binary(path) do
    if File.exists?(path),
      do: {:ok, String.to_charlist(path)},
      else: {:error, {:file_not_found, path}}
  end

  defp read_exck_chunk(beam) do
    case :beam_lib.all_chunks(beam) do
      {:ok, _mod, chunks} ->
        case Enum.find(chunks, fn {name, _} -> IO.chardata_to_string(name) == "ExCk" end) do
          {_, data} -> {:ok, data}
          nil -> {:error, :no_exck_chunk}
        end

      {:error, _, reason} ->
        {:error, reason}
    end
  end

  defp decode_exck(binary) do
    case :erlang.binary_to_term(binary) do
      {version, %{exports: exports}} when version in @supported_versions ->
        {:ok, exports}

      {version, _} ->
        {:error, {:unsupported_checker_version, version}}

      _ ->
        {:error, :invalid_exck_format}
    end
  end

  # -- Private: Signature decoding -------------------------------------------

  defp decode_signature({:infer, _domain, clauses}) do
    Enum.map(clauses, fn {arg_types, return_type} ->
      args = Enum.map(arg_types, &decode_type/1)
      ret = decode_type(return_type)
      {args, ret}
    end)
  end

  defp decode_signature(_), do: []

  # -- Private: Type map decoding --------------------------------------------

  # A type map may contain multiple keys (:bitmap, :atom, :tuple, :list, :map, :fun)
  # representing a union of the encoded types.

  defp decode_type_map(map) do
    parts = []

    parts = if bm = Map.get(map, :bitmap), do: parts ++ decode_bitmap(bm), else: parts
    parts = if at = Map.get(map, :atom), do: parts ++ [decode_atom_type(at)], else: parts
    parts = if tp = Map.get(map, :tuple), do: parts ++ [decode_tuple_type(tp)], else: parts
    parts = if ls = Map.get(map, :list), do: parts ++ [decode_list_type(ls)], else: parts
    parts = if mp = Map.get(map, :map), do: parts ++ [decode_map_type(mp)], else: parts
    parts = if fn_ = Map.get(map, :fun), do: parts ++ [decode_fun_type(fn_)], else: parts

    case parts do
      [] -> [Type.none()]
      _ -> parts
    end
  end

  # -- Bitmap decoding -------------------------------------------------------

  defp decode_bitmap(bitmap) when is_integer(bitmap) do
    for {flag, kind} <- @bitmap_types, Bitwise.band(bitmap, flag) != 0 do
      %Type{kind: kind}
    end
  end

  # -- Atom type decoding ----------------------------------------------------

  defp decode_atom_type({:union, atom_map}) when is_map(atom_map) do
    atoms = Map.keys(atom_map)

    case atoms do
      [single] -> Type.atom(single)
      many -> Type.union(Enum.map(many, &Type.atom/1))
    end
  end

  defp decode_atom_type({:negation, _}), do: Type.atom()
  defp decode_atom_type(_), do: Type.atom()

  # -- Tuple type decoding ---------------------------------------------------

  defp decode_tuple_type({:closed, elements}) do
    Type.tuple(Enum.map(elements, &decode_type/1))
  end

  defp decode_tuple_type({:open, elements}) do
    Type.open_tuple(Enum.map(elements, &decode_type/1))
  end

  defp decode_tuple_type(_), do: %Type{kind: :tuple, params: {:open, []}}

  # -- List type decoding ----------------------------------------------------

  defp decode_list_type({elem_type, _tail_type}) do
    Type.list(decode_type(elem_type))
  end

  defp decode_list_type(:term), do: Type.list()
  defp decode_list_type(_), do: Type.list()

  # -- Map type decoding -----------------------------------------------------

  defp decode_map_type({:open, key_value_pairs}) do
    keys = decode_map_keys(key_value_pairs)
    Type.map(keys, true)
  end

  defp decode_map_type({:closed, key_value_pairs}) do
    keys = decode_map_keys(key_value_pairs)
    Type.map(keys, false)
  end

  # BDD-based map representations -- simplify to open map
  defp decode_map_type({inner, _, _, _}) when is_tuple(inner) do
    decode_map_type(inner)
  end

  defp decode_map_type(_), do: Type.map()

  defp decode_map_keys(pairs) when is_list(pairs) do
    Enum.map(pairs, fn {key, val_type} ->
      {key, decode_type(val_type)}
    end)
  end

  defp decode_map_keys(_), do: []

  # -- Function type decoding ------------------------------------------------

  defp decode_fun_type({:negation, _}), do: %Type{kind: :function, params: []}
  defp decode_fun_type(_), do: %Type{kind: :function, params: []}
end
