defmodule YAMLTest do
  use ExUnit.Case
  doctest YAML

  @yaml_list """
  - name: Ali
    age: 25
  - name: Sara
    age: 22
  """

  @yaml_map """
  name: Ali
  age: 25
  hobbies:
    - Reading
    - Hiking
    - Photography
  """

  @yaml_multi_list """
  - name: Ali
    age: 25
  - name: Sara
    age: 22
  ---
  - name: Rizwan
    age: 24
  """

  @yaml_multi_map """
  name: Ali
  age: 25
  ---
  - name: Rizwan
    age: 24
  """

  describe "decode/2 Single-Document -- input: list[]" do
    setup do
      %{yaml: @yaml_list}
    end

    test "Without option returns list of map (Default)", %{yaml: yaml} do
      assert {:ok,
              [
                %{"name" => "Ali", "age" => 25},
                %{"name" => "Sara", "age" => 22}
              ]} = YAML.decode(yaml)
    end

    test "return: :first_document", %{yaml: yaml} do
      assert {:ok,
              [
                %{"name" => "Ali", "age" => 25},
                %{"name" => "Sara", "age" => 22}
              ]} = YAML.decode(yaml, return: :first_document)
    end

    test "return: :all_documents", %{yaml: yaml} do
      assert {:ok,
              [
                [
                  %{"name" => "Ali", "age" => 25},
                  %{"name" => "Sara", "age" => 22}
                ]
              ]} = YAML.decode(yaml, return: :all_documents)
    end
  end

  describe "decode/2 Single-Document -- input: map %{}" do
    setup do
      %{yaml: @yaml_map}
    end

    test "Without option returns map (Default)", %{yaml: yaml} do
      assert {:ok,
              %{
                "name" => "Ali",
                "age" => 25,
                "hobbies" => ["Reading", "Hiking", "Photography"]
              }} = YAML.decode(yaml)
    end

    test "return: :first_document", %{yaml: yaml} do
      assert {:ok,
              %{
                "name" => "Ali",
                "age" => 25,
                "hobbies" => ["Reading", "Hiking", "Photography"]
              }} = YAML.decode(yaml, return: :first_document)
    end

    test "return: :all_documents wraps map in list", %{yaml: yaml} do
      assert {:ok,
              [
                %{
                  "name" => "Ali",
                  "age" => 25,
                  "hobbies" => ["Reading", "Hiking", "Photography"]
                }
              ]} = YAML.decode(yaml, return: :all_documents)
    end
  end

  describe "decode/2 Multi-Document -- input: list + list" do
    setup do
      %{yaml: @yaml_multi_list}
    end

    test "Without option returns both documents (Default)", %{yaml: yaml} do
      assert {:ok,
              [
                [
                  %{"name" => "Ali", "age" => 25},
                  %{"name" => "Sara", "age" => 22}
                ],
                [
                  %{"name" => "Rizwan", "age" => 24}
                ]
              ]} = YAML.decode(yaml)
    end

    test "return: :first_document returns only first document", %{yaml: yaml} do
      assert {:ok,
              [
                %{"name" => "Ali", "age" => 25},
                %{"name" => "Sara", "age" => 22}
              ]} = YAML.decode(yaml, return: :first_document)
    end

    test "return: :all_documents same as default", %{yaml: yaml} do
      assert {:ok,
              [
                [
                  %{"name" => "Ali", "age" => 25},
                  %{"name" => "Sara", "age" => 22}
                ],
                [
                  %{"name" => "Rizwan", "age" => 24}
                ]
              ]} = YAML.decode(yaml, return: :all_documents)
    end
  end

  describe "decode/2 Multi-Document -- input: map + list" do
    setup do
      %{yaml: @yaml_multi_map}
    end

    test "Without option returns both documents (Default)", %{yaml: yaml} do
      assert {:ok,
              [
                %{"name" => "Ali", "age" => 25},
                [
                  %{"name" => "Rizwan", "age" => 24}
                ]
              ]} = YAML.decode(yaml)
    end

    test "return: :first_document returns only first map document", %{yaml: yaml} do
      assert {:ok, %{"name" => "Ali", "age" => 25}} =
               YAML.decode(yaml, return: :first_document)
    end

    test "return: :all_documents (same as default)", %{yaml: yaml} do
      assert {:ok,
              [
                %{"name" => "Ali", "age" => 25},
                [
                  %{"name" => "Rizwan", "age" => 24}
                ]
              ]} = YAML.decode(yaml, return: :all_documents)
    end
  end
end
