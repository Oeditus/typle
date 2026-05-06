defmodule Typle.MixProject do
  use Mix.Project

  @version "0.3.1"
  @source_url "https://github.com/Oeditus/typle"
  @homepage_url "https://github.com/Oeditus/typle"

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
      docs: docs(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      name: "Typle",
      source_url: @source_url,
      homepage_url: @homepage_url
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
      {:ex_panda, "~> 0.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp description do
    """
    Expression-level type query library for Elixir 1.20+.
    Reads inferred type signatures from compiled .beam files
    and performs best-effort type inference to answer
    "what type is this expression?"
    """
  end

  defp package do
    [
      name: "typle",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      maintainers: ["Oeditus Team"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "stuff/img/logo-48x48.png",
      assets: %{"stuff/img" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @homepage_url,
      formatters: ["html"],
      groups_for_modules: [
        "Public API": [Typle, Typle.ExprMap],
        "Type System": [Typle.Type],
        "Beam Reader": [Typle.Beam, Typle.SignatureStore],
        "Inference Engine": [
          Typle.Inference,
          Typle.Inference.Env,
          Typle.Inference.Expander,
          Typle.Inference.Expr,
          Typle.Inference.Pattern,
          Typle.Inference.Guard,
          Typle.Inference.Builtins
        ],
        Diagnostics: [Typle.Diagnostic],
        "Unstable (opt-in)": [
          Typle.Unstable
        ],
        "Mix Tasks": [
          Mix.Tasks.Typle,
          Mix.Tasks.Typle.Dump
        ]
      ],
      nest_modules_by_prefix: [Typle.Inference]
    ]
  end
end
