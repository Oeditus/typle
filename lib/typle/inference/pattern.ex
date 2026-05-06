defmodule Typle.Inference.Pattern do
  @moduledoc """
  Extracts variable type bindings from pattern matches.

  Given a pattern AST and the type of the expression being matched,
  produces a map of `%{var_name => inferred_type}`.
  """

  alias Typle.Type

  @type bindings :: %{atom() => Type.t()}

  @doc """
  Infers variable types from a pattern, given the type of the matched expression.

  Returns a map of variable names to their inferred types.
  """
  @spec infer(Macro.t(), Type.t()) :: bindings()
  def infer(pattern, matched_type) do
    do_infer(pattern, matched_type, %{})
  end

  # Variable binding: x = <matched_type>
  defp do_infer({var_name, _meta, ctx}, matched_type, bindings)
       when is_atom(var_name) and is_atom(ctx) and var_name != :_ do
    Map.put(bindings, var_name, matched_type)
  end

  # Underscore -- no binding
  defp do_infer({:_, _meta, _ctx}, _matched_type, bindings), do: bindings

  # Match operator: pattern = expr (both sides get the matched type)
  defp do_infer({:=, _meta, [left, right]}, matched_type, bindings) do
    bindings = do_infer(left, matched_type, bindings)
    do_infer(right, matched_type, bindings)
  end

  # Pin operator: ^x -- no new binding
  defp do_infer({:^, _meta, [_]}, _matched_type, bindings), do: bindings

  # Tuple pattern: {a, b, c}
  defp do_infer({:{}, _meta, elements}, _matched_type, bindings) do
    Enum.reduce(elements, bindings, fn elem, acc ->
      do_infer(elem, Type.dynamic(), acc)
    end)
  end

  # Two-element tuple shorthand: {a, b}
  defp do_infer({left, right}, _matched_type, bindings) do
    bindings = do_infer(left, Type.dynamic(), bindings)
    do_infer(right, Type.dynamic(), bindings)
  end

  # List pattern: [head | tail]
  defp do_infer([{:|, _meta, [head, tail]}], matched_type, bindings) do
    elem_type =
      case matched_type do
        %Type{kind: :list, params: et} -> et
        _ -> Type.dynamic()
      end

    bindings = do_infer(head, elem_type, bindings)
    do_infer(tail, matched_type, bindings)
  end

  # List pattern: [a, b, c]
  defp do_infer(elements, matched_type, bindings) when is_list(elements) do
    elem_type =
      case matched_type do
        %Type{kind: :list, params: et} -> et
        _ -> Type.dynamic()
      end

    Enum.reduce(elements, bindings, fn elem, acc ->
      do_infer(elem, elem_type, acc)
    end)
  end

  # Map/struct pattern: %{key: value} or %Mod{key: value}
  defp do_infer({:%{}, _meta, pairs}, _matched_type, bindings) do
    Enum.reduce(pairs, bindings, fn {_key, val}, acc ->
      do_infer(val, Type.dynamic(), acc)
    end)
  end

  defp do_infer({:%, _meta, [_struct_name, {:%{}, _, pairs}]}, _matched_type, bindings) do
    Enum.reduce(pairs, bindings, fn {_key, val}, acc ->
      do_infer(val, Type.dynamic(), acc)
    end)
  end

  # Binary pattern: <<x::binary>>
  defp do_infer({:<<>>, _meta, _segments}, _matched_type, bindings), do: bindings

  # Literal values -- no bindings
  defp do_infer(literal, _matched_type, bindings)
       when is_integer(literal) or is_float(literal) or is_binary(literal) or is_atom(literal) do
    bindings
  end

  # Fallback: unknown pattern shape
  defp do_infer(_other, _matched_type, bindings), do: bindings
end
