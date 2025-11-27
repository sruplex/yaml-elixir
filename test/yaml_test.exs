defmodule YAMLTest do
  use ExUnit.Case
  doctest YAML

  alias YAML.Support.Fixtures

  describe "decode/2" do
    test "no options" do
      yaml = Fixtures.read!(:simple_map)
      assert {:ok, result} = YAML.decode(yaml)

      assert result == %{
               "name" => "Ali",
               "age" => 25,
               "hobbies" => ["Reading", "Hiking", "Photography"]
             }

      yaml = Fixtures.read!(:simple_list)
      assert {:ok, result} = YAML.decode(yaml)
      assert result == [%{"name" => "Ali", "age" => 25}, %{"name" => "Sara", "age" => 22}]

      yaml = Fixtures.read!(:multi_document_two_lists)
      assert {:ok, result} = YAML.decode(yaml)

      assert result == [
               [
                 %{"name" => "Ali", "age" => 25},
                 %{"name" => "Sara", "age" => 22}
               ],
               [
                 %{"name" => "Rizwan", "age" => 24}
               ]
             ]

      yaml = Fixtures.read!(:multi_document_mixed_types)
      assert {:ok, result} = YAML.decode(yaml)

      assert result == [
               %{"name" => "Ali", "age" => 25},
               [
                 %{"name" => "Rizwan", "age" => 24}
               ]
             ]
    end

    test "return: :first_document always returns the first document" do
      yaml = Fixtures.read!(:simple_map)
      assert {:ok, result} = YAML.decode(yaml, return: :first_document)

      assert result == %{
               "name" => "Ali",
               "age" => 25,
               "hobbies" => ["Reading", "Hiking", "Photography"]
             }

      yaml = Fixtures.read!(:simple_list)
      assert {:ok, result} = YAML.decode(yaml, return: :first_document)
      assert result == [%{"name" => "Ali", "age" => 25}, %{"name" => "Sara", "age" => 22}]

      yaml = Fixtures.read!(:multi_document_two_lists)
      assert {:ok, result} = YAML.decode(yaml, return: :first_document)
      assert result == [%{"age" => 25, "name" => "Ali"}, %{"age" => 22, "name" => "Sara"}]

      yaml = Fixtures.read!(:multi_document_mixed_types)
      assert {:ok, result} = YAML.decode(yaml, return: :first_document)
      assert result == %{"age" => 25, "name" => "Ali"}
    end

    test "return: :all_documents always returns the list of all documents" do
      yaml = Fixtures.read!(:simple_map)
      assert {:ok, result} = YAML.decode(yaml, return: :all_documents)

      assert result == [
               %{"age" => 25, "hobbies" => ["Reading", "Hiking", "Photography"], "name" => "Ali"}
             ]

      yaml = Fixtures.read!(:simple_list)
      assert {:ok, result} = YAML.decode(yaml, return: :all_documents)
      assert result == [[%{"age" => 25, "name" => "Ali"}, %{"age" => 22, "name" => "Sara"}]]

      yaml = Fixtures.read!(:multi_document_two_lists)
      assert {:ok, result} = YAML.decode(yaml, return: :all_documents)

      assert result == [
               [
                 %{"name" => "Ali", "age" => 25},
                 %{"name" => "Sara", "age" => 22}
               ],
               [
                 %{"name" => "Rizwan", "age" => 24}
               ]
             ]

      yaml = Fixtures.read!(:multi_document_mixed_types)
      assert {:ok, result} = YAML.decode(yaml, return: :all_documents)

      assert result == [
               %{"name" => "Ali", "age" => 25},
               [
                 %{"name" => "Rizwan", "age" => 24}
               ]
             ]
    end
  end
end
