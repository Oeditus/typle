defmodule Typle.Inference.Builtins do
  @moduledoc """
  Hardcoded type rules for Kernel operators and commonly used stdlib functions.

  These rules are applied during inference even when beam signatures are not
  available, providing a baseline for type propagation through arithmetic,
  comparison, and string operations.
  """

  alias Typle.Type

  @doc """
  Returns the return type for a known builtin call, or nil if unknown.
  """
  @spec return_type(module() | nil, atom(), non_neg_integer(), [Type.t()]) :: Type.t() | nil
  def return_type(module, function, arity, arg_types)

  # -- Kernel arithmetic operators -------------------------------------------

  def return_type(Kernel, op, 2, _args) when op in [:+, :-, :*, :div] do
    Type.dynamic(Type.number())
  end

  def return_type(Kernel, :rem, 2, _args), do: Type.dynamic(Type.integer())
  def return_type(Kernel, :abs, 1, _args), do: Type.dynamic(Type.number())

  def return_type(Kernel, :/, 2, _args), do: Type.dynamic(Type.float())

  # -- Kernel comparison operators -------------------------------------------

  def return_type(Kernel, op, 2, _args)
      when op in [:==, :!=, :===, :!==, :>, :<, :>=, :<=] do
    Type.dynamic(Type.boolean())
  end

  # -- Kernel boolean operators ----------------------------------------------

  def return_type(Kernel, op, 2, _args) when op in [:and, :or] do
    Type.dynamic()
  end

  def return_type(Kernel, :not, 1, _args), do: Type.dynamic(Type.boolean())
  def return_type(Kernel, :!, 1, _args), do: Type.dynamic(Type.boolean())

  # -- Kernel string/binary operators ----------------------------------------

  def return_type(Kernel, :<>, 2, _args), do: Type.dynamic(Type.binary())

  # -- Kernel type checks (return boolean) -----------------------------------

  def return_type(Kernel, fun, 1, _args)
      when fun in [
             :is_integer,
             :is_float,
             :is_number,
             :is_binary,
             :is_bitstring,
             :is_atom,
             :is_boolean,
             :is_list,
             :is_map,
             :is_tuple,
             :is_pid,
             :is_port,
             :is_reference,
             :is_function,
             :is_nil
           ] do
    Type.boolean()
  end

  # -- Kernel misc -----------------------------------------------------------

  def return_type(Kernel, :to_string, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(Kernel, :inspect, 1, _args), do: Type.binary()
  def return_type(Kernel, :inspect, 2, _args), do: Type.binary()
  def return_type(Kernel, :length, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(Kernel, :map_size, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(Kernel, :tuple_size, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(Kernel, :hd, 1, _args), do: Type.dynamic()
  def return_type(Kernel, :tl, 1, _args), do: Type.dynamic(Type.list())
  def return_type(Kernel, :elem, 2, _args), do: Type.dynamic()
  def return_type(Kernel, :put_elem, 3, _args), do: Type.dynamic()

  # -- Integer ---------------------------------------------------------------

  def return_type(Integer, :to_string, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(Integer, :to_string, 2, _args), do: Type.dynamic(Type.binary())

  def return_type(Integer, :parse, 1, _args) do
    Type.dynamic(
      Type.union([
        Type.tuple([Type.integer(), Type.binary()]),
        Type.atom(:error)
      ])
    )
  end

  # -- String ----------------------------------------------------------------

  def return_type(String, :length, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(String, :upcase, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(String, :downcase, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(String, :trim, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(String, :split, 1, _args), do: Type.dynamic(Type.list(Type.binary()))
  def return_type(String, :split, 2, _args), do: Type.dynamic(Type.list(Type.binary()))
  def return_type(String, :split, 3, _args), do: Type.dynamic(Type.list(Type.binary()))
  def return_type(String, :contains?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(String, :starts_with?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(String, :ends_with?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(String, :to_integer, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(String, :to_atom, 1, _args), do: Type.dynamic(Type.atom())

  # -- Enum ------------------------------------------------------------------

  def return_type(Enum, :count, 1, _args), do: Type.dynamic(Type.integer())
  def return_type(Enum, :empty?, 1, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :member?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :any?, 1, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :any?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :all?, 1, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :all?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(Enum, :map, 2, _args), do: Type.dynamic(Type.list())
  def return_type(Enum, :filter, 2, _args), do: Type.dynamic(Type.list())
  def return_type(Enum, :reject, 2, _args), do: Type.dynamic(Type.list())
  def return_type(Enum, :reduce, 2, _args), do: Type.dynamic()
  def return_type(Enum, :reduce, 3, _args), do: Type.dynamic()
  def return_type(Enum, :find, 2, _args), do: Type.dynamic()
  def return_type(Enum, :find, 3, _args), do: Type.dynamic()
  def return_type(Enum, :sort, 1, _args), do: Type.dynamic(Type.list())
  def return_type(Enum, :sort, 2, _args), do: Type.dynamic(Type.list())
  def return_type(Enum, :join, 1, _args), do: Type.dynamic(Type.binary())
  def return_type(Enum, :join, 2, _args), do: Type.dynamic(Type.binary())
  def return_type(Enum, :into, 2, _args), do: Type.dynamic()
  def return_type(Enum, :into, 3, _args), do: Type.dynamic()
  def return_type(Enum, :each, 2, _args), do: Type.atom(:ok)

  # -- Map -------------------------------------------------------------------

  def return_type(Map, :get, 2, _args), do: Type.dynamic()
  def return_type(Map, :get, 3, _args), do: Type.dynamic()
  def return_type(Map, :fetch, 2, _args), do: Type.dynamic()
  def return_type(Map, :fetch!, 2, _args), do: Type.dynamic()
  def return_type(Map, :put, 3, _args), do: Type.dynamic(Type.map())
  def return_type(Map, :delete, 2, _args), do: Type.dynamic(Type.map())
  def return_type(Map, :merge, 2, _args), do: Type.dynamic(Type.map())
  def return_type(Map, :keys, 1, _args), do: Type.dynamic(Type.list())
  def return_type(Map, :values, 1, _args), do: Type.dynamic(Type.list())
  def return_type(Map, :has_key?, 2, _args), do: Type.dynamic(Type.boolean())
  def return_type(Map, :new, 0, _args), do: Type.map([], false)

  # -- IO --------------------------------------------------------------------

  def return_type(IO, :puts, 1, _args), do: Type.atom(:ok)
  def return_type(IO, :puts, 2, _args), do: Type.atom(:ok)
  def return_type(IO, :inspect, 1, [arg_type]), do: arg_type
  def return_type(IO, :inspect, 2, [arg_type, _opts]), do: arg_type

  # -- Fallback: not a known builtin -----------------------------------------

  def return_type(_module, _function, _arity, _args), do: nil
end
