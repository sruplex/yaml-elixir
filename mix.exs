defmodule YAML.MixProject do
  use Mix.Project

  @app :yaml
  @name "YAML"
  @version "0.1.0"
  @github "https://github.com/sruplex/#{@app}"
  @author "Sheharyar Naseer"
  @license "MIT"

  # NOTE:
  # To publish package or update docs, use the `docs`
  # mix environment to not include support modules
  # that are normally included in the `dev` environment
  #
  #   MIX_ENV=docs hex.publish
  #

  def project do
    [
      # Project
      app: @app,
      version: @version,
      elixir: "~> 1.14",
      description: description(),
      package: package(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # ExDoc
      name: @name,
      source_url: @github,
      homepage_url: @github,
      docs: [
        main: @name,
        canonical: "https://hexdocs.pm/#{@app}",
        extras: ["README.md"]
      ]
    ]
  end

  # BEAM Application
  def application do
    [extra_applications: [:logger]]
  end

  # Dependencies
  defp deps do
    [
      {:yamerl, "~> 0.10.0"},
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:inch_ex, ">= 0.0.0", only: :docs}
    ]
  end

  # Compilation Paths
  defp elixirc_paths(:test),
    do: ["lib", "test/support"]

  defp elixirc_paths(_env), do: ["lib"]

  # Package Description
  defp description do
    "YAML Parsing and Encoding in Elixir"
  end

  # Package Information
  defp package do
    [
      name: @app,
      maintainers: [@author],
      licenses: [@license],
      files: ~w(mix.exs lib README.md),
      links: %{"Github" => @github}
    ]
  end
end
