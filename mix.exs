defmodule YAML.MixProject do
  use Mix.Project

  @app :yaml
  @name "YAML"
  @version "0.3.0"
  @github "https://github.com/sruplex/yaml-elixir"

  # NOTE:
  # To publish package or update docs, use the `docs`
  # mix environment to not include support modules
  # that are normally included in the `dev` environment
  #
  #   MIX_ENV=docs mix hex.publish
  #

  def project do
    [
      # Project
      app: @app,
      version: @version,
      elixir: "~> 1.16",
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
        source_ref: "v#{@version}",
        extras: [
          "README.md",
          "guides/cookbook.md",
          "guides/migrating_from_yaml_elixir.md",
          "CHANGELOG.md"
        ],
        groups_for_extras: [Guides: ~r/guides\//]
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
      {:rustler_precompiled, "~> 0.10.1", runtime: false},
      # Only needed to build the native library from source, with YAML_BUILD=true
      {:rustler, "~> 0.38.0", optional: true, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:inch_ex, ">= 0.0.0", only: :docs}
    ]
  end

  # Compilation Paths
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Package Description
  defp description do
    "YAML Parsing and Encoding in Elixir"
  end

  # Package Information
  defp package do
    [
      name: @app,
      maintainers: ["Sruplex", "Sheharyar Naseer"],
      licenses: ["MIT"],
      files: ~w(
        mix.exs lib README.md CHANGELOG.md checksum-Elixir.YAML.Native.exs
        native/yaml_parser/src native/yaml_parser/Cargo.toml native/yaml_parser/Cargo.lock
        native/yaml_parser/.cargo native/yaml_parser/Cross.toml
      ),
      links: %{"GitHub" => @github}
    ]
  end
end
