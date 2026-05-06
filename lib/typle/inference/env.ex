defmodule Typle.Inference.Env do
  @moduledoc """
  Type environment for tracking variable types during inference.

  Maintains a stack of scopes. Each scope maps variable names to their
  inferred types. Entering a `case`, `fn`, `with`, or `try` block
  pushes a new scope; leaving pops it.
  """

  alias Typle.Type

  @type t :: %__MODULE__{
          scopes: [%{atom() => Type.t()}],
          types: %{position() => Type.t()},
          module: module() | nil,
          file: String.t() | nil,
          aliases: %{atom() => module()}
        }

  @type position :: {non_neg_integer(), non_neg_integer()}

  defstruct scopes: [%{}], types: %{}, module: nil, file: nil, aliases: %{}

  @doc "Creates a new empty environment."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      module: Keyword.get(opts, :module),
      file: Keyword.get(opts, :file)
    }
  end

  @doc "Puts a variable type in the current (innermost) scope."
  @spec put_var(t(), atom(), Type.t()) :: t()
  def put_var(%__MODULE__{scopes: [current | rest]} = env, var_name, type) do
    %{env | scopes: [Map.put(current, var_name, type) | rest]}
  end

  @doc "Looks up a variable type, searching from innermost to outermost scope."
  @spec get_var(t(), atom()) :: Type.t()
  def get_var(%__MODULE__{scopes: scopes}, var_name) do
    Enum.find_value(scopes, Type.dynamic(), fn scope ->
      Map.get(scope, var_name)
    end)
  end

  @doc "Pushes a new scope (e.g. entering a case/fn/with block)."
  @spec push_scope(t()) :: t()
  def push_scope(%__MODULE__{scopes: scopes} = env) do
    %{env | scopes: [%{} | scopes]}
  end

  @doc "Pushes a new scope initialized with the given variable bindings."
  @spec push_scope(t(), %{atom() => Type.t()}) :: t()
  def push_scope(%__MODULE__{scopes: scopes} = env, bindings) do
    %{env | scopes: [bindings | scopes]}
  end

  @doc "Pops the innermost scope, returning to the parent."
  @spec pop_scope(t()) :: t()
  def pop_scope(%__MODULE__{scopes: [_ | rest]} = env) when rest != [] do
    %{env | scopes: rest}
  end

  def pop_scope(env), do: env

  @doc "Records the inferred type for an expression at the given position."
  @spec record_type(t(), non_neg_integer(), non_neg_integer(), Type.t()) :: t()
  def record_type(%__MODULE__{types: types} = env, line, col, type) do
    %{env | types: Map.put(types, {line, col}, type)}
  end

  @doc "Returns the type recorded at the given position, or nil."
  @spec type_at(t(), non_neg_integer(), non_neg_integer()) :: Type.t() | nil
  def type_at(%__MODULE__{types: types}, line, col) do
    Map.get(types, {line, col})
  end

  @doc "Returns all recorded types as a map of `{line, col} => type`."
  @spec all_types(t()) :: %{position() => Type.t()}
  def all_types(%__MODULE__{types: types}), do: types

  @doc "Stores an alias mapping (e.g. `Beam` -> `Typle.Beam`)."
  @spec put_alias(t(), atom(), module()) :: t()
  def put_alias(%__MODULE__{aliases: aliases} = env, short, full) do
    %{env | aliases: Map.put(aliases, short, full)}
  end

  @doc "Resolves `{:__aliases__}` parts through the alias map."
  @spec resolve_alias(t(), [atom()]) :: module()
  def resolve_alias(%__MODULE__{aliases: aliases}, [first | rest]) do
    case Map.get(aliases, first) do
      nil -> Module.concat([first | rest])
      resolved -> Module.concat([resolved | rest])
    end
  end

  def resolve_alias(_env, parts), do: Module.concat(parts)

  @doc """
  Merges variable bindings from multiple branches (e.g. case clauses).
  Variables that appear in all branches get the union of their types.
  Variables that appear in only some branches get `dynamic()`.
  """
  @spec merge_branches(t(), [%{atom() => Type.t()}]) :: t()
  def merge_branches(env, []), do: env

  def merge_branches(env, branch_envs) do
    all_vars = branch_envs |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    merged =
      Map.new(all_vars, fn var ->
        types =
          branch_envs
          |> Enum.map(&Map.get(&1, var))
          |> Enum.reject(&is_nil/1)

        type =
          case types do
            [] -> Type.dynamic()
            [single] -> single
            many -> Type.union(many)
          end

        {var, type}
      end)

    Enum.reduce(merged, env, fn {var, type}, acc ->
      put_var(acc, var, type)
    end)
  end
end
