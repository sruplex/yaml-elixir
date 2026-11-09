defmodule YAML.DecoderTest do
  use ExUnit.Case, async: true

  alias YAML.ArgumentError
  alias YAML.Support.{Point, User, Team, Money, Order}

  @team """
  name: core
  lead: {name: Ada, email: ada@example.com}
  members:
    - {name: Bo, email: bo@example.com}
    - {name: Cy}
  """

  describe "as: a struct" do
    test "fills the struct's fields from the matching keys" do
      assert YAML.decode("name: Ada\nemail: ada@example.com", as: %User{}) ==
               {:ok, %User{name: "Ada", email: "ada@example.com"}}
    end

    test "ignores keys that are not fields" do
      assert YAML.decode("x: 1\nz: 3\nnot_an_existing_atom_9f2c: 4", as: %Point{}) ==
               {:ok, %Point{x: 1}}
    end

    test "keeps the default of fields without a key" do
      assert YAML.decode("x: 1", as: %Point{y: 0}) == {:ok, %Point{x: 1, y: 0}}
    end

    test "decodes nested structs and lists of structs from the field defaults" do
      assert YAML.decode(@team, as: %Team{}) ==
               {:ok,
                %Team{
                  name: "core",
                  lead: %User{name: "Ada", email: "ada@example.com"},
                  members: [%User{name: "Bo", email: "bo@example.com"}, %User{name: "Cy"}]
                }}
    end

    test "works with atom keys" do
      assert YAML.decode("x: 1", as: %Point{}, atomize_keys: true) == {:ok, %Point{x: 1}}
    end

    test "leaves a document that is not a map as it is" do
      assert YAML.decode("plain text", as: %Point{}) == {:ok, "plain text"}
      assert YAML.decode("lead: text", as: %Team{}) == {:ok, %Team{lead: "text"}}
    end
  end

  describe "as: a list" do
    test "decodes each item into the struct" do
      assert YAML.decode("- {x: 1, y: 2}\n- {x: 3}", as: [%Point{}]) ==
               {:ok, [%Point{x: 1, y: 2}, %Point{x: 3}]}
    end
  end

  describe "documents" do
    test "each document is decoded into the struct" do
      assert YAML.decode("x: 1\n---\nx: 2", as: %Point{}) == {:ok, [%Point{x: 1}, %Point{x: 2}]}

      assert YAML.decode("x: 1\n---\nx: 2", as: %Point{}, return: :first_document) ==
               {:ok, %Point{x: 1}}
    end

    test "each streamed document is decoded into the struct" do
      assert ["x: 1\n---\n", "x: 2\n"] |> YAML.decode_stream!(as: %Point{}) |> Enum.to_list() ==
               [%Point{x: 1}, %Point{x: 2}]
    end
  end

  describe "round trip" do
    test "encoding and decoding gives the struct back" do
      {:ok, team} = YAML.decode(@team, as: %Team{})
      assert YAML.decode!(YAML.encode!(team), as: %Team{}) == team
    end

    test "structs in lists inside a struct field are encoded" do
      team = %Team{name: "core", lead: %User{name: "Ada"}, members: [%User{name: "Bo"}]}

      assert YAML.encode(team, sort_maps: true) ==
               {:ok,
                """
                ---
                lead:
                  email: null
                  name: Ada
                members:
                  - email: null
                    name: Bo
                name: core
                """}
    end
  end

  describe "defimpl" do
    test "decodes a value that is not a map into the struct" do
      assert YAML.decode("id: 1\nprice: 12.50 USD", as: %Order{}) ==
               {:ok, %Order{id: 1, price: %Money{amount: "12.50", currency: "USD"}}}
    end

    test "is used for each item of a list" do
      assert YAML.decode("- 1 USD\n- 2 EUR", as: [%Money{}]) ==
               {:ok, [%Money{amount: "1", currency: "USD"}, %Money{amount: "2", currency: "EUR"}]}
    end

    test "encoding and decoding gives the struct back" do
      order = %Order{id: 2, price: %Money{amount: "3.10", currency: "EUR"}}
      assert YAML.decode!(YAML.encode!(order), as: %Order{}) == order
    end
  end

  describe "invalid options" do
    test "as: must be a struct or a list of one struct" do
      for value <- [:point, %{}, [], [%Point{}, %Point{}], "x"] do
        assert {:error, %ArgumentError{option: :as, value: ^value}} =
                 YAML.decode("x: 1", as: value)
      end
    end

    test "as: is not supported with detailed: true" do
      assert {:error,
              %ArgumentError{option: :as, message: "is not supported with detailed: true"}} =
               YAML.decode("x: 1", as: %Point{}, detailed: true)
    end
  end
end
