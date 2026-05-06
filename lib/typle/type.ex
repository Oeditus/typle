defmodule Typle.Type do
  @moduledoc """
  Representation of Elixir set-theoretic types.

  Each type is a struct with a `kind` field indicating the type category
  and a `params` field carrying kind-specific data. The `dynamic?` flag
  indicates whether the type is wrapped in `dynamic()`.
  """

  import Kernel, except: [to_string: 1]

  @type kind ::
          :integer
          | :float
          | :binary
          | :bitstring
          | :atom
          | :tuple
          | :list
          | :empty_list
          | :map
          | :function
          | :pid
          | :port
          | :reference
          | :union
          | :intersection
          | :negation
          | :none
          | :term

  @type t :: %__MODULE__{
          kind: kind(),
          params: term(),
          dynamic?: boolean()
        }

  defstruct kind: :term, params: nil, dynamic?: false

  # -- Constructors ----------------------------------------------------------

  @doc "Returns the `term()` type (top type, set of all values)."
  @spec term() :: t()
  def term, do: %__MODULE__{kind: :term}

  @doc "Returns the `none()` type (bottom type, empty set)."
  @spec none() :: t()
  def none, do: %__MODULE__{kind: :none}

  @doc "Returns `dynamic()` or `dynamic(inner)`."
  @spec dynamic(t()) :: t()
  def dynamic(%__MODULE__{} = inner \\ term()), do: %{inner | dynamic?: true}

  @doc "Returns the `integer()` type."
  @spec integer() :: t()
  def integer, do: %__MODULE__{kind: :integer}

  @doc "Returns the `float()` type."
  @spec float() :: t()
  def float, do: %__MODULE__{kind: :float}

  @doc "Returns `integer() or float()` -- the number type."
  @spec number() :: t()
  def number, do: union([integer(), float()])

  @doc "Returns the `binary()` type."
  @spec binary() :: t()
  def binary, do: %__MODULE__{kind: :binary}

  @doc "Returns the `bitstring()` type."
  @spec bitstring() :: t()
  def bitstring, do: %__MODULE__{kind: :bitstring}

  @doc "Returns the `pid()` type."
  @spec pid() :: t()
  def pid, do: %__MODULE__{kind: :pid}

  @doc "Returns the `port()` type."
  @spec port() :: t()
  def port, do: %__MODULE__{kind: :port}

  @doc "Returns the `reference()` type."
  @spec reference() :: t()
  def reference, do: %__MODULE__{kind: :reference}

  @doc "Returns `true or false` -- the boolean type."
  @spec boolean() :: t()
  def boolean, do: union([atom(true), atom(false)])

  @doc "Returns the `atom()` type, optionally with a literal value."
  @spec atom(atom() | nil) :: t()
  def atom(literal \\ nil), do: %__MODULE__{kind: :atom, params: literal}

  @doc "Returns a closed tuple type with the given element types."
  @spec tuple(list(t())) :: t()
  def tuple(elements), do: %__MODULE__{kind: :tuple, params: {:closed, elements}}

  @doc "Returns an open tuple type (at least the given elements, possibly more)."
  @spec open_tuple(list(t())) :: t()
  def open_tuple(elements), do: %__MODULE__{kind: :tuple, params: {:open, elements}}

  @doc "Returns a `list()` type with the given element type (defaults to `term()`)."
  @spec list(t()) :: t()
  def list(elem_type \\ term()), do: %__MODULE__{kind: :list, params: elem_type}

  @doc "Returns the `empty_list()` type."
  @spec empty_list() :: t()
  def empty_list, do: %__MODULE__{kind: :empty_list}

  @doc "Returns a `map()` type with optional keys and open/closed flag."
  @spec map(keyword(), boolean()) :: t()
  def map(keys \\ [], open? \\ true), do: %__MODULE__{kind: :map, params: {keys, open?}}

  @doc "Returns a `function()` type with the given clauses."
  @spec function(list({list(t()), t()})) :: t()
  def function(clauses), do: %__MODULE__{kind: :function, params: clauses}

  @doc "Returns a union of the given types. Single-element unions collapse."
  @spec union(list(t())) :: t()
  def union([single]), do: single

  def union(types) do
    flat =
      types
      |> Enum.flat_map(fn
        %__MODULE__{kind: :union, params: inner} -> inner
        other -> [other]
      end)
      |> Enum.uniq()

    case flat do
      [single] -> single
      many -> %__MODULE__{kind: :union, params: many}
    end
  end

  @doc "Returns an intersection of the given types. Single-element intersections collapse."
  @spec intersection(list(t())) :: t()
  def intersection([single]), do: single
  def intersection(types), do: %__MODULE__{kind: :intersection, params: types}

  @doc "Returns the negation of the given type."
  @spec negation(t()) :: t()
  def negation(type), do: %__MODULE__{kind: :negation, params: type}

  # -- Predicates ------------------------------------------------------------

  @doc "Returns `true` if the type represents the unknown/top type."
  @spec term?(t()) :: boolean()
  def term?(%__MODULE__{kind: :term}), do: true
  def term?(_), do: false

  @doc "Returns `true` if the type represents the empty/bottom type."
  @spec none?(t()) :: boolean()
  def none?(%__MODULE__{kind: :none}), do: true
  def none?(_), do: false

  # -- Formatting ------------------------------------------------------------

  @doc """
  Formats the type using Elixir's type notation.

  ## Examples

      iex> Typle.Type.to_string(Typle.Type.integer())
      "integer()"

      iex> Typle.Type.to_string(Typle.Type.union([Typle.Type.atom(:ok), Typle.Type.atom(:error)]))
      ":error or :ok"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{dynamic?: true} = type) do
    inner = %{type | dynamic?: false}

    case inner.kind do
      :term -> "dynamic()"
      _ -> "dynamic(#{to_string(inner)})"
    end
  end

  def to_string(%__MODULE__{kind: kind, params: params}) do
    format_kind(kind, params)
  end

  defp format_kind(:term, _), do: "term()"
  defp format_kind(:none, _), do: "none()"
  defp format_kind(:integer, _), do: "integer()"
  defp format_kind(:float, _), do: "float()"
  defp format_kind(:binary, _), do: "binary()"
  defp format_kind(:bitstring, _), do: "bitstring()"
  defp format_kind(:pid, _), do: "pid()"
  defp format_kind(:port, _), do: "port()"
  defp format_kind(:reference, _), do: "reference()"
  defp format_kind(:empty_list, _), do: "empty_list()"

  defp format_kind(:atom, nil), do: "atom()"
  defp format_kind(:atom, true), do: "true"
  defp format_kind(:atom, false), do: "false"
  defp format_kind(:atom, literal), do: inspect(literal)

  defp format_kind(:tuple, {:closed, elements}) do
    inner = Enum.map_join(elements, ", ", &to_string/1)
    "{#{inner}}"
  end

  defp format_kind(:tuple, {:open, elements}) do
    inner = Enum.map_join(elements, ", ", &to_string/1)
    "{#{inner}, ...}"
  end

  defp format_kind(:list, elem_type) do
    "list(#{to_string(elem_type)})"
  end

  defp format_kind(:map, {[], true}), do: "map()"
  defp format_kind(:map, {[], false}), do: "empty_map()"

  defp format_kind(:map, {keys, open?}) do
    prefix = if open?, do: "..., ", else: ""

    fields =
      Enum.map_join(keys, ", ", fn
        {key, val_type} when is_atom(key) -> "#{key}: #{to_string(val_type)}"
        {key_type, val_type} -> "#{to_string(key_type)} => #{to_string(val_type)}"
      end)

    "%{#{prefix}#{fields}}"
  end

  defp format_kind(:function, clauses) do
    clauses
    |> Enum.map_join(" and ", fn {args, ret} ->
      arg_str = Enum.map_join(args, ", ", &to_string/1)
      "(#{arg_str} -> #{to_string(ret)})"
    end)
  end

  defp format_kind(:union, types) do
    types
    |> Enum.sort_by(&to_string/1)
    |> Enum.map_join(" or ", &to_string/1)
  end

  defp format_kind(:intersection, types) do
    types
    |> Enum.map_join(" and ", &to_string/1)
  end

  defp format_kind(:negation, type) do
    "not #{to_string(type)}"
  end

  defimpl Inspect do
    def inspect(type, _opts) do
      "#Typle.Type<#{Typle.Type.to_string(type)}>"
    end
  end

  defimpl String.Chars do
    def to_string(type), do: Typle.Type.to_string(type)
  end
end
