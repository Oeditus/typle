defmodule Typle.TypePropertiesTest do
  @moduledoc """
  Property-based tests for `Typle.Type`'s algebraic laws.

  `union/1` and `to_string/1` are pure, total, and have real laws, which makes
  them a much better fit for generated inputs than the hand-picked examples in
  `type_test.exs`. The `to_string/1` properties in particular guard the
  `union([])` defect: an empty union used to render as `""`.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Typle.Type

  # A generator covering every `kind` the formatter knows about, including the
  # The leaf types: no nested `Type.t()` inside, so this generator is not
  # recursive and can be used as the base of the `tree/2` below.
  defp leaf_type_gen do
    one_of([
      constant(Type.term()),
      constant(Type.none()),
      constant(Type.integer()),
      constant(Type.float()),
      constant(Type.binary()),
      constant(Type.bitstring()),
      constant(Type.empty_list()),
      constant(Type.pid()),
      constant(Type.port()),
      constant(Type.reference()),
      constant(Type.atom()),
      constant(Type.number()),
      constant(Type.boolean()),
      map(atom(:alphanumeric), &Type.atom/1)
    ])
  end

  # Types that contain other types, built one level up from `inner`.
  defp composite_type_gen(inner) do
    one_of([
      map(list_of(inner, max_length: 3), &Type.tuple/1),
      map(list_of(inner, max_length: 3), &Type.open_tuple/1),
      map(inner, &Type.dynamic/1),
      map(inner, &Type.list/1),
      map(inner, &Type.negation/1)
    ])
  end

  defp scalar_type_gen, do: leaf_type_gen()

  defp type_gen do
    tree(leaf_type_gen(), &composite_type_gen/1)
  end

  describe "union/1" do
    property "is commutative under to_string/1" do
      check all(a <- scalar_type_gen(), b <- scalar_type_gen()) do
        assert Type.to_string(Type.union([a, b])) == Type.to_string(Type.union([b, a]))
      end
    end

    property "is idempotent under to_string/1" do
      check all(a <- scalar_type_gen()) do
        assert Type.to_string(Type.union([a, a])) == Type.to_string(Type.union([a]))
      end
    end

    property "is associative under to_string/1" do
      check all(
              a <- scalar_type_gen(),
              b <- scalar_type_gen(),
              c <- scalar_type_gen()
            ) do
        left = Type.union([Type.union([a, b]), c])
        right = Type.union([a, Type.union([b, c])])

        assert Type.to_string(left) == Type.to_string(right)
      end
    end

    property "never produces an empty rendered type" do
      # Regression guard: `union/1` used to have no `[]` clause, so
      # `union([])` built a `:union` with no members and `to_string/1`
      # returned the empty string -- an invalid type that then propagated
      # silently into query results.
      check all(types <- list_of(scalar_type_gen())) do
        refute Type.to_string(Type.union(types)) == ""
      end
    end

    property "collapses a single-element union to that element" do
      check all(a <- scalar_type_gen()) do
        assert Type.union([a]) == a
      end
    end
  end

  describe "to_string/1" do
    property "is never empty for any constructed type" do
      check all(a <- type_gen()) do
        refute Type.to_string(a) == ""
      end
    end

    property "is deterministic" do
      check all(a <- type_gen()) do
        assert Type.to_string(a) == Type.to_string(a)
      end
    end

    property "never renders a dangling separator" do
      # Regression guard: `open_tuple([])` rendered as "{, ...}" because the
      # template assumed at least one element. A leading comma inside braces or
      # a trailing comma before the closing brace is never valid notation.
      check all(a <- type_gen()) do
        rendered = Type.to_string(a)
        refute rendered =~ ~r/\{\s*,/
        refute rendered =~ ~r/,\s*\}/
        refute rendered =~ ~r/\{\s*\.\.\.\s*,/
      end
    end
  end

  describe "dynamic/1" do
    property "always renders with a dynamic() wrapper" do
      check all(a <- scalar_type_gen()) do
        rendered = Type.to_string(Type.dynamic(a))
        assert String.starts_with?(rendered, "dynamic(")
        assert String.ends_with?(rendered, ")")
      end
    end

    property "is idempotent on the flag" do
      check all(a <- scalar_type_gen()) do
        assert Type.dynamic(Type.dynamic(a)) == Type.dynamic(a)
      end
    end
  end

  describe "intersection/1" do
    property "collapses a single-element intersection to that element" do
      check all(a <- scalar_type_gen()) do
        assert Type.intersection([a]) == a
      end
    end

    property "never produces an empty rendered type" do
      check all(types <- list_of(scalar_type_gen())) do
        refute Type.to_string(Type.intersection(types)) == ""
      end
    end
  end

  describe "predicates" do
    property "term?/1 and none?/1 are mutually exclusive" do
      check all(a <- type_gen()) do
        refute Type.term?(a) and Type.none?(a)
      end
    end
  end
end
