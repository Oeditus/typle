<img src="https://raw.githubusercontent.com/Oeditus/typle/v0.1.0/stuff/img/logo-128x128.png" alt="Oeditus Typle" width="128" align="right">

# Typle

[![Hex.pm](https://img.shields.io/hexpm/v/typle.svg)](https://hex.pm/packages/typle)
[![CI](https://github.com/Oeditus/typle/actions/workflows/ci.yml/badge.svg)](https://github.com/Oeditus/typle/actions/workflows/ci.yml)

**Expression-level type query library for Elixir 1.20+.**

Typle reads inferred type signatures from compiled `.beam` files and performs
best-effort type inference to answer the question the Elixir compiler can answer
internally but does not expose:

> “What type did the compiler infer for this expression at line N, column C?”

## The Problem

Elixir 1.20 introduced a powerful set-theoretic type system that infers types
across function definitions, guards, patterns, and clauses. The compiler uses
these types to detect bugs at compile time—but the type information lives
exclusively inside the compiler. There is no public API to query it.

- **The ExCk chunk** in `.beam` files stores per-function signatures, but not
  per-expression types.
- **Compilation tracers** fire events for imports, aliases, and module
  definitions—but carry no type data.
- **`Module.Types`** and its submodules are private (`@moduledoc false`) and
  subject to change without notice.

Tools like Credo, LSPs, and custom Mix tasks that need type information are
left in the dark.

## How Typle Works

Typle operates in layers, from most stable to most experimental:

### Layer 1: Beam Signature Reader (`Typle.Beam`)

Reads the `:elixir_checker_v7` data from the ‘ExCk’ chunk in compiled `.beam`
files. Decodes the internal bitmap/map type representation into human-friendly
`Typle.Type` structs. This gives you per-function signatures for any compiled
module.

### Layer 2: Signature Store (`Typle.SignatureStore`)

An ETS-backed cache of decoded function signatures. Lazily loads modules on
first lookup. Used by the inference engine to resolve return types for remote
function calls.

### Layer 3: AST Inference Engine (`Typle.Inference`)

Parses Elixir source files and walks the AST, simulating the compiler's type
inference. Tracks variable types through assignments, pattern matches, guard
checks, and function calls. Produces a map of `{line, col} => Typle.Type.t()`
for every expression with position metadata.

The engine handles: literals, variables, match operators, pipes, remote/local
calls, `case`/`cond`/`if`/`with`/`try`/`fn` expressions, tuples, lists, maps,
structs, and binary constructions.

### Layer 3.5: Macro Expansion (`Typle.Inference.Expander`)

Before walking the AST, function bodies are expanded via
[ExPanda](https://hexdocs.pm/ex_panda) to resolve all macros to their
underlying forms. This means pipe chains (`|>`), `unless`, `use` directives,
library DSLs, and custom macros are expanded before inference, giving the
engine visibility into the actual control flow and data flow. Expansion
failures are handled gracefully -- if a macro cannot be expanded (e.g. the
defining module is not loaded), the original AST is preserved and the
inference engine applies its existing best-effort handling.

### Layer 4: Unstable Compiler Replay (`Typle.Unstable`)

An opt-in layer that hooks into the compiler via compilation tracers for
deeper inference. Lives under the `Typle.Unstable` namespace to signal that
it depends on private APIs and may break across Elixir versions.

## Installation

Add `typle` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:typle, "~> 0.1"}
  ]
end
```

Typle requires **Elixir 1.20** or later.

## Usage

### Programmatic API

```elixir
# Read function signatures from a compiled module
{:ok, sigs} = Typle.signatures(Integer)
# => [%{fun: :to_string, arity: 1, clauses: [{[integer()], dynamic(binary())}]}, ...]

# Look up the return type of a function
Typle.return_type(Integer, :to_string, 1)
# => #Typle.Type<dynamic(binary())>

# Infer types for all expressions in a source file
{:ok, type_map} = Typle.types_for_file("lib/my_app/user.ex")
# => %{{15, 5} => #Typle.Type<binary()>, {16, 3} => #Typle.Type<integer()>, ...}

# Query the type at a specific position
{:ok, type} = Typle.type_at("lib/my_app/user.ex", 15, 5)
# => #Typle.Type<binary()>
```

### Mix Tasks

```bash
# Query type at a specific position
mix typle lib/my_app/user.ex:15:5
# => lib/my_app/user.ex:15:5 :: binary()

# Query all types on a line
mix typle lib/my_app/user.ex:15
# =>   col 3: user :: dynamic()
# =>   col 8: user.name :: dynamic()

# Dump all types for a module
mix typle.dump MyApp.User

# Output as JSON (for LSP/tooling consumption)
mix typle lib/my_app/user.ex:15:5 --format json

# Use the unstable compiler replay for deeper inference
mix typle lib/my_app/user.ex:15:5 --unstable
```

### Integration with Credo

A Credo check can call `Typle.type_at/3` to verify the inferred type of a
suspicious expression before raising an issue:

```elixir
defmodule MyApp.Credo.Check.TypeAware do
  use Credo.Check

  def run(%SourceFile{filename: file} = source_file, params) do
    # Use Typle to get type information
    case Typle.type_at(file, line, col) do
      {:ok, %Typle.Type{kind: :binary}} -> :ok
      {:ok, other_type} -> issue_for(source_file, line, col, other_type)
      _ -> :ok
    end
  end
end
```

## Type Notation

Typle formats types using the same notation as the Elixir compiler:

| Type | Notation |
|------|----------|
| Integer | `integer()` |
| Float | `float()` |
| Binary/String | `binary()` |
| Atom | `atom()`, `:ok`, `true`, `false` |
| Tuple | `{:ok, integer()}` |
| List | `list(integer())` |
| Map | `map()`, `%{..., name: binary()}` |
| Function | `(integer() -> binary())` |
| Union | `integer() or binary()` |
| Dynamic | `dynamic()`, `dynamic(binary())` |
| Top | `term()` |
| Bottom | `none()` |

## Limitations

Typle's inference engine is a **best-effort approximation** of what the Elixir
compiler computes. It will never achieve perfect parity because:

- The compiler's type checker is tightly integrated with macro expansion,
  module compilation order, and cross-module dependency resolution.
- Per-expression type environments are ephemeral—they exist only during
  the compiler's type checking pass and are discarded afterward.
- The ‘ExCk’ chunk format (`:elixir_checker_v7`) is internal and undocumented;
  it may change in future Elixir releases.

When Typle cannot determine a type, it honestly returns `dynamic()` rather
than guessing wrong.

## Not yet implemented

- [ ] Type annotations / signatures (Elixir does not yet have user-facing type syntax)
- [ ] Protocol dispatch type tracking
- [ ] Cross-module dataflow analysis beyond function signatures

## License

MIT License. See [LICENSE](LICENSE) for details.
