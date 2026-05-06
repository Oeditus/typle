# Changelog

All notable changes to this project will be documented in this file.

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
