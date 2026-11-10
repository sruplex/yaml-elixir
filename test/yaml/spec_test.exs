defmodule YAML.SpecTest do
  # The yaml-test-suite cases, cloned by CI with:
  #   git clone --depth 1 --branch data-2022-01-17 https://github.com/yaml/yaml-test-suite tmp/yaml-test-suite
  use ExUnit.Case, async: true

  @dir "tmp/yaml-test-suite"

  # Cases we don't pass yet, with the reason
  @known_failures %{
    "565N" => "!!binary decodes to raw bytes, the suite's JSON has the base64 text"
  }

  if not File.dir?(@dir) and System.get_env("CI") do
    raise "the yaml-test-suite is missing from #{@dir}"
  end

  cases =
    for path <- Path.wildcard(Path.join(@dir, "**/in.yaml")),
        dir = Path.dirname(path),
        name = Path.relative_to(dir, @dir),
        not String.starts_with?(name, ["name/", "tags/"]),
        do: {name, dir}

  for {name, dir} <- cases do
    @external_resource Path.join(dir, "in.yaml")
    @tag spec: name
    test "#{name}: #{File.read!(Path.join(dir, "==="))}" do
      dir = unquote(dir)
      yaml = File.read!(Path.join(dir, "in.yaml"))
      result = YAML.decode(yaml, return: :all_documents, enable_merge: false)

      cond do
        File.exists?(Path.join(dir, "error")) ->
          assert {:error, %YAML.ParsingError{}} = result

        File.exists?(Path.join(dir, "in.json")) ->
          expected = dir |> Path.join("in.json") |> File.read!() |> json_documents()

          if Map.has_key?(@known_failures, unquote(name)) do
            assert result != {:ok, expected}, "now passes, remove it from @known_failures"
          else
            assert result == {:ok, expected}
          end

        true ->
          assert {:ok, _} = result
      end
    end
  end

  # The suite's in.json holds one JSON value per document
  defp json_documents(text) do
    text
    |> String.trim()
    |> Stream.unfold(fn
      "" ->
        nil

      text ->
        {value, :ok, rest} = :json.decode(text, :ok, %{null: nil})
        {value, String.trim(rest)}
    end)
    |> Enum.to_list()
  end
end
