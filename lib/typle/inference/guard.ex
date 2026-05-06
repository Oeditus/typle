defmodule Typle.Inference.Guard do
  @moduledoc """
  Refines variable types based on guard expressions.

  Analyzes guard AST to narrow the types of variables that appear
  in type-checking guards like `is_integer/1`, `is_binary/1`, etc.
  """

  alias Typle.Type

  @type refinements :: %{atom() => Type.t()}

  @guard_type_map %{
    :is_integer => :integer,
    :is_float => :float,
    :is_number => nil,
    :is_binary => :binary,
    :is_bitstring => :bitstring,
    :is_atom => :atom,
    :is_boolean => nil,
    :is_list => :list,
    :is_map => :map,
    :is_tuple => :tuple,
    :is_pid => :pid,
    :is_port => :port,
    :is_reference => :reference,
    :is_function => :function,
    :is_nil => nil
  }

  @doc """
  Analyzes a guard expression and returns type refinements for variables.

  Returns a map of `%{var_name => refined_type}`.
  """
  @spec refine(Macro.t()) :: refinements()
  def refine(guard_ast) do
    do_refine(guard_ast, %{})
  end

  # is_X(var) guards
  defp do_refine({guard_fn, _meta, [{var_name, _, ctx}]}, refinements)
       when is_atom(var_name) and is_atom(ctx) and is_map_key(@guard_type_map, guard_fn) do
    type = guard_to_type(guard_fn)
    Map.update(refinements, var_name, type, &Type.intersection([&1, type]))
  end

  # is_map_key(var, key)
  defp do_refine({:is_map_key, _meta, [{var_name, _, ctx}, key]}, refinements)
       when is_atom(var_name) and is_atom(ctx) and is_atom(key) do
    map_type = Type.map([{key, Type.dynamic()}], true)
    Map.update(refinements, var_name, map_type, &Type.intersection([&1, map_type]))
  end

  # and -- intersect refinements from both sides
  defp do_refine({:and, _meta, [left, right]}, refinements) do
    left_refs = do_refine(left, refinements)
    do_refine(right, left_refs)
  end

  # andalso -- same as and
  defp do_refine({:andalso, _meta, [left, right]}, refinements) do
    left_refs = do_refine(left, refinements)
    do_refine(right, left_refs)
  end

  # or -- union refinements from both sides
  defp do_refine({:or, _meta, [left, right]}, refinements) do
    left_refs = do_refine(left, %{})
    right_refs = do_refine(right, %{})

    all_vars = Map.keys(left_refs) ++ Map.keys(right_refs)

    merged =
      Map.new(Enum.uniq(all_vars), fn var ->
        left_type = Map.get(left_refs, var)
        right_type = Map.get(right_refs, var)

        type =
          case {left_type, right_type} do
            {nil, t} -> t
            {t, nil} -> t
            {l, r} -> Type.union([l, r])
          end

        {var, type}
      end)

    Map.merge(refinements, merged)
  end

  # orelse -- same as or
  defp do_refine({:orelse, _meta, [left, right]}, refinements) do
    do_refine({:or, [], [left, right]}, refinements)
  end

  # not -- we could negate, but for best-effort we skip negation
  defp do_refine({:not, _meta, [_inner]}, refinements), do: refinements

  # Comparison guards (x > 0, etc.) -- refine to number
  defp do_refine({op, _meta, [{var_name, _, ctx}, _]}, refinements)
       when op in [:>, :<, :>=, :<=] and is_atom(var_name) and is_atom(ctx) do
    Map.put_new(refinements, var_name, Type.number())
  end

  defp do_refine({op, _meta, [_, {var_name, _, ctx}]}, refinements)
       when op in [:>, :<, :>=, :<=] and is_atom(var_name) and is_atom(ctx) do
    Map.put_new(refinements, var_name, Type.number())
  end

  # when clause with multiple guards (semicolon-separated)
  defp do_refine({:when, _meta, [inner, rest]}, refinements) do
    refinements = do_refine(inner, refinements)
    do_refine(rest, refinements)
  end

  # Anything else -- no refinement
  defp do_refine(_other, refinements), do: refinements

  # -- Helpers ---------------------------------------------------------------

  defp guard_to_type(:is_integer), do: Type.integer()
  defp guard_to_type(:is_float), do: Type.float()
  defp guard_to_type(:is_number), do: Type.number()
  defp guard_to_type(:is_binary), do: Type.binary()
  defp guard_to_type(:is_bitstring), do: Type.bitstring()
  defp guard_to_type(:is_atom), do: Type.atom()
  defp guard_to_type(:is_boolean), do: Type.boolean()
  defp guard_to_type(:is_list), do: Type.list()
  defp guard_to_type(:is_map), do: Type.map()
  defp guard_to_type(:is_tuple), do: %Type{kind: :tuple, params: {:open, []}}
  defp guard_to_type(:is_pid), do: Type.pid()
  defp guard_to_type(:is_port), do: Type.port()
  defp guard_to_type(:is_reference), do: Type.reference()
  defp guard_to_type(:is_function), do: %Type{kind: :function, params: []}
  defp guard_to_type(:is_nil), do: Type.atom(nil)
  defp guard_to_type(_), do: Type.dynamic()
end
