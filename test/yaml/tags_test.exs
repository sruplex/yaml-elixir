defmodule YAML.TagsTest do
  use ExUnit.Case, async: true

  alias YAML.ArgumentError
  alias YAML.Support.{Money, Order}

  def money(text) do
    [amount, currency] = String.split(text, " ")
    %Money{amount: amount, currency: currency}
  end

  @tags %{"!money" => &__MODULE__.money/1, "!set" => &MapSet.new/1}

  describe "tags:" do
    test "replaces a tagged scalar with the function's result" do
      assert YAML.decode("price: !money 12.50 USD", tags: @tags) ==
               {:ok, %{"price" => %Money{amount: "12.50", currency: "USD"}}}
    end

    test "passes a tagged list or map after its values are decoded" do
      assert YAML.decode("ids: !set [1, 1, 2]", tags: @tags) ==
               {:ok, %{"ids" => MapSet.new([1, 2])}}

      assert YAML.decode("p: !pair {a: 1}", tags: %{"!pair" => &Map.to_list/1}) ==
               {:ok, %{"p" => [{"a", 1}]}}
    end

    test "handles tags inside other tagged values" do
      assert YAML.decode("!set [!money 1 USD, !money 1 USD]", tags: @tags) ==
               {:ok, MapSet.new([%Money{amount: "1", currency: "USD"}])}
    end

    test "handles tagged keys" do
      assert YAML.decode("!money 1 USD: paid", tags: @tags) ==
               {:ok, %{%Money{amount: "1", currency: "USD"} => "paid"}}
    end

    test "keeps tags without a function as they are" do
      assert YAML.decode("a: !other 12.50", tags: @tags) == {:ok, %{"a" => "12.50"}}
    end

    test "works with values from an alias and a merge" do
      yaml = "base: &b {price: !money 1 USD}\ncopy:\n  <<: *b\n"

      assert YAML.decode(yaml, tags: @tags) ==
               {:ok,
                %{
                  "base" => %{"price" => %Money{amount: "1", currency: "USD"}},
                  "copy" => %{"price" => %Money{amount: "1", currency: "USD"}}
                }}
    end

    test "runs before as:" do
      assert YAML.decode("id: 1\nprice: !money 2 EUR", as: %Order{}, tags: @tags) ==
               {:ok, %Order{id: 1, price: %Money{amount: "2", currency: "EUR"}}}
    end

    test "works when streaming" do
      stream = YAML.decode_stream!(["a: !set [1]\n---\n", "b: !set [2]\n"], tags: @tags)

      assert Enum.to_list(stream) == [%{"a" => MapSet.new([1])}, %{"b" => MapSet.new([2])}]
    end

    test "is ignored with detailed: true" do
      {:ok, doc} = YAML.decode("!set [1]", tags: @tags, detailed: true)
      assert doc.root.meta.tag == "!set"
    end

    test "raises the function's own error" do
      assert_raise MatchError, fn -> YAML.decode("!money 12.50", tags: @tags) end
    end

    test "returns an error for an invalid value" do
      assert {:error, %ArgumentError{option: :tags}} = YAML.decode("a", tags: [])
      assert {:error, %ArgumentError{option: :tags}} = YAML.decode("a", tags: %{"!a" => 1})
      assert {:error, %ArgumentError{option: :tags}} = YAML.decode("a", tags: %{a: &MapSet.new/1})

      assert {:error, %ArgumentError{option: :tags}} =
               YAML.decode("a", tags: %{"!a" => &Map.put/3})
    end
  end
end
