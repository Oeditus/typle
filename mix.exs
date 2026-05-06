defmodule Typle.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Oeditus/typle"

  def project do
    [
      app: :typle,
      version: @version,
      elixir: ">= 1.20.0-rc.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Typle",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Expression-level type query library for Elixir 1.20+.
    Reads inferred type signatures from compiled `.beam` files
    and performs best-effort type inference to answer
    “what type is this expression?”
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
