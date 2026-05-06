defmodule Typle.Test.SampleModule do
  @moduledoc false
  # A sample module used by tests to verify type inference.
  # Do NOT compile this as a regular module -- it is read as source text.

  def add(a, b) when is_integer(a) and is_integer(b) do
    a + b
  end

  def greet(name) when is_binary(name) do
    "Hello, " <> name
  end

  def maybe_parse(input) do
    case Integer.parse(input) do
      {num, _rest} -> {:ok, num}
      :error -> {:error, :invalid}
    end
  end

  def identity(%{} = x), do: x
  def identity(x), do: x
end
