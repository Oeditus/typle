defmodule Typle.Test.MacroModule do
  @moduledoc false
  # A sample module exercising macros that ExPanda should expand.
  # Used by tests to verify that macro expansion improves type inference.

  def piped(x) when is_integer(x) do
    x
    |> Integer.to_string()
    |> String.upcase()
  end

  def conditional(x) do
    unless x do
      :fallback
    end
  end

  def negated(x) do
    if x do
      "no"
    else
      "yes"
    end
  end

  def chained(list) when is_list(list) do
    list
    |> Enum.map(fn item -> item end)
    |> Enum.count()
  end
end
