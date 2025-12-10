defmodule YAMLTest do
  use ExUnit.Case
  doctest YAML

  alias YAML.Support.Fixtures

  describe "decode/2" do
    setup do
      :yamerl_app.set_param(:node_mods, [
        :yamerl_node_timestamp,
        :yamerl_node_size,
        :yamerl_node_ipaddr
      ])
    end

    test "no options" do
      decode_yaml_with_options()
      |> hd()
      |> verify_first_document_structure
    end

    test "return: :first_document always returns the first document" do
      decode_yaml_with_options(return: :first_document)
      |> verify_first_document_structure()
    end

    test "return: :all_documents always returns the list of all documents" do
      decode_yaml_with_options(return: :all_documents)
      |> hd()
      |> verify_first_document_structure
    end

    test "detailed: true returns AST" do
      assert %YAML.AST.Document{root: %YAML.AST.Mapping{}} =
               decode_yaml_with_options(detailed: true) |> List.last()
    end

    test "detailed: false or without option return elixir data structure" do
      decode_yaml_with_options(detailed: false)
      |> hd()
      |> verify_first_document_structure
    end
  end

  defp verify_first_document_structure(document) do
    assert %{
             "binary_data" => "Hello WORLD",
             "created_at" => ~N[2025-01-01 12:30:45],
             "ipv4" => {192, 168, 1, 10},
             "active" => true,
             "middle_name" => nil
           } = document
  end

  defp decode_yaml_with_options(opts \\ []) do
    yaml = Fixtures.read!(:multi_document_mixed_types)
    assert {:ok, result} = YAML.decode(yaml, opts)
    result
  end
end
