defmodule Typle.Inference.Pattern do
  @moduledoc """
  Extracts variable type bindings from pattern matches.

  Given a pattern AST and the type of the expression being matched,
  narrows the type to the subset compatible with the pattern structure,
  decomposes composite types (tuples, lists, maps) into their element
  types, and propagates those types to bound variables.

  Also records the inferred type at each variable's source position
  so that `Typle.type_at/3` can report pattern-variable types.
  """

  alias Typle.Type

  @type bindings :: %{atom() => Type.t()}
  @type positions :: %{{non_neg_integer(), non_neg_integer()} => Type.t()}

  @doc """
  Infers variable types from a pattern, given the type of the matched expression.

  Returns `{bindings, positions}` where `bindings` maps variable names to
  their inferred types and `positions` maps `{line, col}` to the type at
  that source location.
  """
  @spec infer(Macro.t(), Type.t()) :: {bindings(), positions()}
  def infer(pattern, matched_type) do
    do_infer(pattern, matched_type, {%{}, %{}})
  end

  # -- Pattern clauses --------------------------------------------------------

  # Variable binding: x = <matched_type>
  defp do_infer({var_name, meta, ctx}, matched_type, {bindings, positions})
       when is_atom(var_name) and is_atom(ctx) and var_name != :_ do
    positions = record_position(positions, meta, matched_type)
    {Map.put(bindings, var_name, matched_type), positions}
  end

  # Underscore -- no binding
  defp do_infer({:_, _meta, _ctx}, _matched_type, acc), do: acc

  # Match operator: pattern = expr (both sides get the matched type)
  defp do_infer({:=, _meta, [left, right]}, matched_type, acc) do
    acc = do_infer(left, matched_type, acc)
    do_infer(right, matched_type, acc)
  end

  # Pin operator: ^x -- no new binding
  defp do_infer({:^, _meta, [_]}, _matched_type, acc), do: acc

  # Tuple pattern: {a, b, c, ...} (3+ elements)
  defp do_infer({:{}, _meta, elements}, matched_type, acc) do
    narrowed = narrow(matched_type, {:tuple, length(elements)})

    elements
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {elem, idx}, acc ->
      elem_type = extract_tuple_element(narrowed, idx)
      do_infer(elem, elem_type, acc)
    end)
  end

  # Two-element tuple shorthand: {a, b}
  defp do_infer({left, right}, matched_type, acc) do
    narrowed = narrow(matched_type, {:tuple, 2})
    acc = do_infer(left, extract_tuple_element(narrowed, 0), acc)
    do_infer(right, extract_tuple_element(narrowed, 1), acc)
  end

  # List pattern: [head | tail]
  defp do_infer([{:|, _meta, [head, tail]}], matched_type, acc) do
    narrowed = narrow(matched_type, :list)
    elem_type = extract_list_element(narrowed)
    acc = do_infer(head, elem_type, acc)
    do_infer(tail, narrowed, acc)
  end

  # List pattern: [a, b, c]
  defp do_infer(elements, matched_type, acc) when is_list(elements) do
    narrowed = narrow(matched_type, :list)
    elem_type = extract_list_element(narrowed)

    Enum.reduce(elements, acc, fn elem, acc ->
      do_infer(elem, elem_type, acc)
    end)
  end

  # Map pattern: %{key: value}
  defp do_infer({:%{}, _meta, pairs}, matched_type, acc) do
    narrowed = narrow(matched_type, :map)

    Enum.reduce(pairs, acc, fn {key, val}, acc ->
      val_type = extract_map_value(narrowed, key)
      do_infer(val, val_type, acc)
    end)
  end

  # Struct pattern: %Mod{key: value}
  defp do_infer({:%, _meta, [_struct_name, {:%{}, _, pairs}]}, matched_type, acc) do
    narrowed = narrow(matched_type, :map)

    Enum.reduce(pairs, acc, fn {key, val}, acc ->
      val_type = extract_map_value(narrowed, key)
      do_infer(val, val_type, acc)
    end)
  end

  # Binary pattern: <<x::binary>>
  defp do_infer({:<<>>, _meta, _segments}, _matched_type, acc), do: acc

  # Literal values -- no bindings
  defp do_infer(literal, _matched_type, acc)
       when is_integer(literal) or is_float(literal) or is_binary(literal) or is_atom(literal) do
    acc
  end

  # Fallback: unknown pattern shape
  defp do_infer(_other, _matched_type, acc), do: acc

  # -- Type narrowing ---------------------------------------------------------
  #
  # Given a type and a pattern shape descriptor, returns the subset of the
  # type that is structurally compatible with the pattern.

  # dynamic(inner): strip wrapper, narrow inner, re-wrap
  defp narrow(%Type{dynamic?: true} = type, shape) do
    inner = %{type | dynamic?: false}

    case narrow(inner, shape) do
      %Type{kind: :none} -> Type.dynamic()
      narrowed -> %{narrowed | dynamic?: true}
    end
  end

  # union: filter members, rebuild
  defp narrow(%Type{kind: :union, params: types}, shape) do
    narrowed = Enum.filter(types, &shape_matches?(&1, shape))

    case narrowed do
      [] -> Type.dynamic()
      [single] -> single
      many -> Type.union(many)
    end
  end

  # concrete type: check shape compatibility
  defp narrow(type, shape) do
    if shape_matches?(type, shape), do: type, else: Type.dynamic()
  end

  # -- Shape matching predicates ----------------------------------------------

  defp shape_matches?(%Type{dynamic?: true} = type, shape) do
    shape_matches?(%{type | dynamic?: false}, shape)
  end

  defp shape_matches?(%Type{kind: :tuple, params: {:closed, elems}}, {:tuple, arity}) do
    length(elems) == arity
  end

  defp shape_matches?(%Type{kind: :tuple, params: {:open, elems}}, {:tuple, arity}) do
    length(elems) <= arity
  end

  defp shape_matches?(%Type{kind: :list}, :list), do: true
  defp shape_matches?(%Type{kind: :empty_list}, :list), do: true
  defp shape_matches?(%Type{kind: :map}, :map), do: true
  defp shape_matches?(%Type{kind: :term}, _shape), do: true

  # Recurse into unions
  defp shape_matches?(%Type{kind: :union, params: types}, shape) do
    Enum.any?(types, &shape_matches?(&1, shape))
  end

  defp shape_matches?(_type, _shape), do: false

  # -- Element extraction -----------------------------------------------------

  @doc false
  # Extracts the type at a given index from a (possibly union/dynamic) tuple type.
  def extract_tuple_element(%Type{dynamic?: true} = type, index) do
    inner = %{type | dynamic?: false}

    case extract_tuple_element(inner, index) do
      %Type{dynamic?: true} = t -> t
      t -> %{t | dynamic?: true}
    end
  end

  def extract_tuple_element(%Type{kind: :tuple, params: {:closed, elems}}, index) do
    Enum.at(elems, index) || Type.dynamic()
  end

  def extract_tuple_element(%Type{kind: :tuple, params: {:open, elems}}, index) do
    Enum.at(elems, index) || Type.dynamic()
  end

  def extract_tuple_element(%Type{kind: :union, params: types}, index) do
    types
    |> Enum.map(&extract_tuple_element(&1, index))
    |> Type.union()
  end

  def extract_tuple_element(_type, _index), do: Type.dynamic()

  defp extract_list_element(%Type{dynamic?: true} = type) do
    inner = %{type | dynamic?: false}

    case extract_list_element(inner) do
      %Type{dynamic?: true} = t -> t
      t -> %{t | dynamic?: true}
    end
  end

  defp extract_list_element(%Type{kind: :list, params: elem_type}), do: elem_type

  defp extract_list_element(%Type{kind: :union, params: types}) do
    types
    |> Enum.map(&extract_list_element/1)
    |> Type.union()
  end

  defp extract_list_element(_type), do: Type.dynamic()

  defp extract_map_value(%Type{dynamic?: true} = type, key) do
    inner = %{type | dynamic?: false}

    case extract_map_value(inner, key) do
      %Type{dynamic?: true} = t -> t
      t -> %{t | dynamic?: true}
    end
  end

  defp extract_map_value(%Type{kind: :map, params: {keys, _open?}}, key) when is_atom(key) do
    case List.keyfind(keys, key, 0) do
      {^key, val_type} -> val_type
      nil -> Type.dynamic()
    end
  end

  defp extract_map_value(%Type{kind: :union, params: types}, key) do
    types
    |> Enum.map(&extract_map_value(&1, key))
    |> Type.union()
  end

  defp extract_map_value(_type, _key), do: Type.dynamic()

  # -- Position recording -----------------------------------------------------

  defp record_position(positions, meta, type) do
    line = Keyword.get(meta, :line, 0)
    col = Keyword.get(meta, :column, 0)

    if line > 0 do
      Map.put(positions, {line, col}, type)
    else
      positions
    end
  end
end
