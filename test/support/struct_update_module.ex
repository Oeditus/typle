defmodule Typle.Test.StructUpdateModule do
  @moduledoc false
  # Regression fixture for constructs that used to crash inference or the
  # macro expander. Read as source text -- do NOT compile as a regular module.

  def update_struct(data, issues) do
    %{data | issues: issues}
  end

  def update_struct_two(data, issues, other) do
    %{data | issues: issues, other: other}
  end

  def plain_map do
    %{a: 1, b: 2}
  end

  def inline_with(x) do
    with {:ok, a} <- x, do: a
  end

  def block_with(x) do
    with {:ok, a} <- x do
      a
    end
  end

  def with_else(x) do
    # credo:disable-for-next-line Credo.Check.Readability.WithSingleClause
    with {:ok, a} <- x do
      a
    else
      _ -> :error
    end
  end

  def comprehension(list) do
    for {_k, v} <- list, v > 0, do: v * 2
  end

  def comprehension_into(list) do
    for v <- list, into: %{}, do: {v, v}
  end
end
