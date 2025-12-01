defmodule YAML.Support.Fixtures do
  @moduledoc """
  Helper module for loading YAML fixture files in tests.
  """

  @fixtures_path "test/support/fixtures"

  @doc """
  Reads a fixture file by name.

  ## Examples

      iex> Fixtures.read!(:simple_map)
      "name: Ali\\nage: 25\\n..."

  """
  def read!(name) do
    @fixtures_path
    |> Path.join("#{name}.yml")
    |> File.read!()
  end
end
