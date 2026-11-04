# Changelog

All notable changes to this project will be documented in this file.

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- **Inference crashed on struct update syntax.** `%{struct | key: value}` parses
  as `{:%{}, _, [{:|, _, [struct, [key: value]]}]}` -- the map-literal clause
  destructured each element as `{key, value}` and raised `FunctionClauseError`
  on the bare `:|` tuple, taking down inference for the whole file. Struct
  updates are ubiquitous in real Elixir (16.6% of files in the Ragex codebase
  use them), so this affected roughly a fifth of all files.
- **`with` and `for` expanded to invalid AST.** The macro expander appended the
  body options with `clauses ++ opts`, splicing the `{key, value}` pairs in
  individually and producing `[clause, {:do, body}]` instead of
  `[clause, [do: body]]`. The result was AST that `Macro.to_string/1` cannot
  even print, which crashed every consumer that renders or walks it. Both
  `split_with_clauses/1` and `split_for_clauses/1` also mishandled a body
  arriving as a bare `{:do, body}` tuple or wrapped in an extra list.
- **`elixir_checker_v8` was rejected.** Elixir 1.20.4 emits `ExCk` chunks
  tagged `:elixir_checker_v8`, but only `v7` was accepted, so
  `Typle.Beam.read_signatures/1` failed with
  `{:unsupported_checker_version, :elixir_checker_v8}` on current compilers.
  v8 differs only in storing `exports` as a list of `{key, value}` tuples
  rather than a map; both are now normalised to the same shape.

## [0.1.0] - 2026-05-06

### Added

- `Typle.Type` -- set-theoretic type representation with constructors, formatting, `Inspect` and `String.Chars` protocol implementations.
- `Typle.Beam` -- ExCk chunk reader that decodes the `:elixir_checker_v7` format from compiled `.beam` files into `Typle.Type` structs.
- `Typle.SignatureStore` -- ETS-backed cache of function type signatures with lazy module loading.
- `Typle.Inference` -- AST-walking type inference engine with support for:
  - Literals, variables, match operators, pipes
  - Remote and local function calls
  - Pattern match type narrowing (`Typle.Inference.Pattern`)
  - Guard-based type refinement (`Typle.Inference.Guard`)
  - `case`/`cond`/`if`/`with`/`try`/`fn` expressions
  - Tuples, lists, maps, structs, binaries
- `Typle.Inference.Builtins` -- hardcoded type rules for 100+ functions from Kernel, Integer, String, Enum, Map, and IO.
- `Typle.Diagnostic` -- compiler diagnostic capture and type violation extraction.
- `Typle.Unstable` -- opt-in compiler replay layer with version pinning (Elixir 1.20.x).
- `mix typle` -- point and line type queries with `--format text|json` and `--unstable` flags.
- `mix typle.dump` -- full module type dump.
- Public API: `Typle.type_at/3`, `Typle.types_for/1`, `Typle.types_for_file/1`, `Typle.signatures/1`, `Typle.return_type/3`.
