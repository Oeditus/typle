defmodule Typle do
  @moduledoc """
  Expression-level type query library for Elixir 1.20+.

  Reads inferred type signatures from compiled `.beam` files and performs
  best-effort type inference to answer "what type does the compiler think
  this expression has at line N, column C?"

  ## Usage

      # Point query
      Typle.type_at("lib/my_app/user.ex", 15, 5)
      #=> {:ok, %Typle.Type{kind: :binary}}

      # Full module map
      Typle.types_for(MyApp.User)
      #=> {:ok, %{{15, 5} => %Typle.Type{kind: :binary}, ...}}

      # Read function signatures from a compiled module
      Typle.signatures(Integer)
      #=> {:ok, [%{fun: :to_string, arity: 1, clauses: ...}, ...]}

  For deeper inference using compiler internals (opt-in, unstable),
  see `Typle.Unstable`.
  """

  alias Typle.{Beam, Inference, SignatureStore, Type}

  @doc """
  Returns the inferred type at the given file position.

  Uses the stable inference engine (AST walking + signature store).
  """
  @spec type_at(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Type.t()} | {:error, term()}
  def type_at(file, line, col) do
    with {:ok, type_map} <- Inference.infer_file(file) do
      case Map.get(type_map, {line, col}) do
        nil -> {:error, :no_type_at_position}
        type -> {:ok, type}
      end
    end
  end

  @doc """
  Returns all inferred types for a module.

  Returns a map of `{line, col} => Typle.Type.t()` for each expression
  in the module's source file.
  """
  @spec types_for(module()) :: {:ok, Inference.type_map()} | {:error, term()}
  def types_for(module) do
    Inference.infer_module(module)
  end

  @doc """
  Returns all inferred types for a source file.
  """
  @spec types_for_file(String.t()) :: {:ok, Inference.type_map()} | {:error, term()}
  def types_for_file(file) do
    Inference.infer_file(file)
  end

  @doc """
  Reads function signatures from a compiled module's `.beam` file.

  Returns the decoded type signatures as stored in the ExCk chunk.
  """
  @spec signatures(module() | String.t()) :: {:ok, [Beam.signature()]} | {:error, term()}
  def signatures(module_or_path) do
    Beam.read_signatures(module_or_path)
  end

  @doc """
  Looks up the return type of a function call.

  Queries the signature store for `module.function/arity` and returns
  the inferred return type.
  """
  @spec return_type(module(), atom(), non_neg_integer()) :: Type.t()
  def return_type(module, function, arity) do
    SignatureStore.return_type(module, function, arity, [])
  end
end
