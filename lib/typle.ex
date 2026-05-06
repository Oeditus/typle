defmodule Typle do
  @moduledoc """
  Expression-level type query library for Elixir 1.20+.

  Reads inferred type signatures from compiled `.beam` files and performs
  best-effort type inference to answer "what type does the compiler think
  this expression has at line N, column C?"

  Before inference, all macros in function bodies are expanded via
  [ExPanda](https://hexdocs.pm/ex_panda), so pipe chains, `unless`,
  `use` directives, and library DSLs are resolved to their underlying
  forms. When expansion fails, the original AST is preserved and
  inference falls back to its existing best-effort handling.

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

  alias Typle.{Beam, Inference, SignatureStore, Type, Unstable}

  @doc """
  Returns the inferred type at the given file position.

  Uses the stable inference engine (AST walking + signature store).

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
  """
  @spec type_at(String.t(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, Type.t()} | {:error, term()}
  def type_at(file, line, col, opts \\ []) do
    if opts[:unstable] do
      Unstable.type_at(file, line, col)
    else
      with {:ok, type_map} <- Inference.infer_file(file),
           :error <- Map.fetch(type_map, {line, col}),
           do: {:error, :no_type_at_position}
    end
  end

  @doc """
  Returns all inferred types for a module.

  Returns a map of `{line, col} => Typle.Type.t()` for each expression
  in the module's source file.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
  """
  @spec types_for(module(), keyword()) :: {:ok, Inference.type_map()} | {:error, term()}
  def types_for(module, opts \\ []) do
    if opts[:unstable] do
      Unstable.types_for(module)
    else
      Inference.infer_module(module)
    end
  end

  @doc """
  Returns all inferred types for a source file.

  ## Options

    * `:unstable` - when `true`, uses the compiler-replay engine
      from `Typle.Unstable` for deeper inference (default: `false`)
  """
  @spec types_for_file(String.t(), keyword()) :: {:ok, Inference.type_map()} | {:error, term()}
  def types_for_file(file, opts \\ []) do
    if opts[:unstable] do
      Unstable.types_for_file(file)
    else
      Inference.infer_file(file)
    end
  end

  @doc """
  Reads function signatures from a compiled module's `.beam` file.

  Returns the decoded type signatures as stored in the ExCk chunk.

  ## Options

    * `:unstable` - accepted for API consistency but currently
      has no effect (signatures are always read from BEAM chunks)
  """
  @spec signatures(module() | String.t(), keyword()) ::
          {:ok, [Beam.signature()]} | {:error, term()}
  def signatures(module_or_path, opts \\ []) do
    _ = opts
    Beam.read_signatures(module_or_path)
  end

  @doc """
  Looks up the return type of a function call.

  Queries the signature store for `module.function/arity` and returns
  the inferred return type.

  ## Options

    * `:unstable` - accepted for API consistency but currently
      has no effect (return types are always resolved via the signature store)
  """
  @spec return_type(module(), atom(), non_neg_integer(), keyword()) :: Type.t()
  def return_type(module, function, arity, opts \\ []) do
    _ = opts
    SignatureStore.return_type(module, function, arity, [])
  end
end
