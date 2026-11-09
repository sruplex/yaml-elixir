defmodule YAML.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  # Downloads the prebuilt library for this platform; builds it in this repo, or with YAML_BUILD=true
  use RustlerPrecompiled,
    otp_app: :yaml,
    crate: "yaml_parser",
    base_url: "https://github.com/sruplex/yaml-elixir/releases/download/v#{version}",
    force_build: System.get_env("YAML_BUILD") in ["1", "true"] or Mix.env() in [:dev, :test],
    version: version,
    nif_versions: ["2.15"],
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      arm-unknown-linux-gnueabihf
      riscv64gc-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-pc-windows-gnu
      x86_64-pc-windows-msvc
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    )

  # Both return {:ok, documents} or {:error, message, line, column}; parse_dirty runs on a dirty scheduler
  def parse(_yaml, _schema), do: :erlang.nif_error(:nif_not_loaded)
  def parse_dirty(_yaml, _schema), do: :erlang.nif_error(:nif_not_loaded)
end
