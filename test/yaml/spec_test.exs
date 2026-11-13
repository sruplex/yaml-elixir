defmodule YAML.SpecTest do
  # The yaml-test-suite cases, which need OTP 27 for :json, cloned with:
  #   git clone --depth 1 --branch data-2022-01-17 https://github.com/yaml/yaml-test-suite tmp/yaml-test-suite
  use ExUnit.Case, async: true

  @dir "tmp/yaml-test-suite"

  # Cases with !!binary values, which the suite's JSON can only show as base64 text
  @binary_cases ["565N"]

  if not File.dir?(@dir) and System.get_env("CI") do
    raise "the yaml-test-suite is missing from #{@dir}"
  end

  # The name/ and tags/ folders link to the same cases
  cases =
    for path <- Path.wildcard(Path.join(@dir, "**/in.yaml")),
        dir = Path.dirname(path),
        name = Path.relative_to(dir, @dir),
        not String.starts_with?(name, ["name/", "tags/"]),
        do: {name, dir}

  for {name, dir} <- cases do
    @tag spec: name
    test "#{name}: #{String.trim(File.read!(Path.join(dir, "===")))}" do
      dir = unquote(dir)
      yaml = File.read!(Path.join(dir, "in.yaml"))
      # YAML 1.2 has no merge key
      result = YAML.decode(yaml, return: :all_documents, enable_merge: false)

      cond do
        File.exists?(Path.join(dir, "error")) ->
          assert {:error, %YAML.ParsingError{}} = result

        File.exists?(Path.join(dir, "in.json")) ->
          # The suite's in.json holds one JSON value per document
          expected =
            dir
            |> Path.join("in.json")
            |> File.read!()
            |> String.trim()
            |> Stream.unfold(fn
              "" ->
                nil

              text ->
                {value, :ok, rest} = :json.decode(text, :ok, %{null: nil})
                {value, String.trim(rest)}
            end)
            |> Enum.to_list()

          expected =
            if unquote(name) in @binary_cases, do: decode_base64(expected), else: expected

          # == as the suite's JSON writes a float such as 450.00 as 450
          assert result == {:ok, expected}

        # Cases with keys JSON can't hold, such as maps or null, only check that they decode
        true ->
          assert {:ok, _} = result
      end
    end
  end

  # Turns the base64 text of the suite's JSON into bytes, as !!binary decodes
  defp decode_base64(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, decode_base64(v)} end)

  defp decode_base64(list) when is_list(list), do: Enum.map(list, &decode_base64/1)

  defp decode_base64(text) when is_binary(text) do
    case Base.decode64(text, ignore: :whitespace) do
      {:ok, bytes} -> bytes
      :error -> text
    end
  end

  defp decode_base64(value), do: value
end
