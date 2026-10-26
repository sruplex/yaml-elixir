defmodule YAML.BuilderTest do
  use ExUnit.Case, async: true

  alias YAML.Builder
  alias YAML.EncodeError
  alias YAML.AST.{Document, Scalar, List, Mapping}

  @tag_prefix "tag:yaml.org,2002:"

  defp root(term) do
    assert {:ok, %Document{root: root}} = Builder.build(term)
    root
  end

  defp tag(node), do: String.replace_prefix(node.meta.tag, @tag_prefix, "")

  defp build_error(term) do
    assert {:error, %EncodeError{} = error} = Builder.build(term)
    error
  end

  describe "scalars" do
    test "nil, booleans, integers and floats get their own tags" do
      for {term, expected_tag} <- [
            {nil, "null"},
            {true, "bool"},
            {false, "bool"},
            {42, "int"},
            {-7, "int"},
            {1.5, "float"}
          ] do
        assert %Scalar{value: ^term} = node = root(term)
        assert tag(node) == expected_tag
      end
    end

    test "infinity and NaN atoms are floats, as decode returns them" do
      for special <- [:"+inf", :"-inf", :nan] do
        assert %Scalar{value: ^special} = node = root(special)
        assert tag(node) == "float"
      end
    end
  end

  describe "strings and atoms" do
    test "strings are str scalars" do
      for string <- ["hello", "", "123"] do
        assert %Scalar{value: ^string} = node = root(string)
        assert tag(node) == "str"
      end
    end

    test "atoms become str scalars" do
      assert %Scalar{value: "ok"} = node = root(:ok)
      assert tag(node) == "str"
    end
  end

  describe "lists" do
    test "builds items and length" do
      assert %List{items: [%Scalar{value: 1}, %Scalar{value: "a"}], length: 2} =
               node = root([1, "a"])

      assert tag(node) == "seq"
    end

    test "empty list" do
      assert %List{items: [], length: 0} = root([])
    end

    test "nested lists" do
      assert %List{items: [%List{items: [%Scalar{value: 1}], length: 1}], length: 1} = root([[1]])
    end
  end

  describe "maps" do
    test "builds pairs" do
      assert %Mapping{pairs: [{%Scalar{value: "a"}, %Scalar{value: 1}}]} =
               node = root(%{"a" => 1})

      assert tag(node) == "map"
    end

    test "empty map" do
      assert %Mapping{pairs: []} = root(%{})
    end

    test "nested maps and lists" do
      assert %Mapping{pairs: [{%Scalar{value: "a"}, %Mapping{pairs: [{_, %List{length: 1}}]}}]} =
               root(%{"a" => %{"b" => [1]}})
    end
  end

  describe "map keys" do
    test "strings, atoms, numbers, nil and booleans are allowed" do
      for {key, expected_tag} <- [
            {"a", "str"},
            {:a, "str"},
            {1, "int"},
            {1.5, "float"},
            {nil, "null"},
            {true, "bool"}
          ] do
        assert %Mapping{pairs: [{key_node, _}]} = root(%{key => 1})
        assert tag(key_node) == expected_tag
      end
    end

    test "other keys return an invalid_key error" do
      for {key, type} <- [{{1, 2}, "tuple"}, {[1], "list"}, {%{}, "map"}] do
        error = build_error(%{key => 1})
        assert error.cause == :invalid_key
        assert error.term == key
        assert error.message == "cannot encode #{type} as a map key"
      end
    end
  end

  describe "dates and times" do
    test "become ISO 8601 str scalars" do
      for {term, iso} <- [
            {~D[2026-10-14], "2026-10-14"},
            {~T[10:00:00], "10:00:00"},
            {~N[2026-10-14 10:00:00], "2026-10-14T10:00:00"},
            {~U[2026-10-14 10:00:00Z], "2026-10-14T10:00:00Z"}
          ] do
        assert %Scalar{value: ^iso} = node = root(term)
        assert tag(node) == "str"
      end
    end

    test "DateTime keeps its offset" do
      datetime = %{
        ~U[2026-10-14 15:00:00Z]
        | utc_offset: 18_000,
          time_zone: "Asia/Karachi",
          zone_abbr: "PKT"
      }

      assert %Scalar{value: "2026-10-14T15:00:00+05:00"} = root(datetime)
    end
  end

  describe "unsupported values" do
    test "return an unsupported_type error" do
      for {term, type} <- [
            {{1, 2}, "tuple"},
            {self(), "pid"},
            {make_ref(), "reference"},
            {&IO.puts/1, "function"},
            {%URI{}, "URI struct"},
            {<<1::3>>, "bitstring"}
          ] do
        error = build_error(term)
        assert error.cause == :unsupported_type
        assert error.term == term
        assert error.message == "cannot encode #{type}"
      end
    end

    test "improper lists return an error with the bad tail" do
      error = build_error([1 | 2])
      assert error.cause == :unsupported_type
      assert error.term == 2
      assert error.message == "cannot encode improper list"
    end

    test "nested errors are returned with their location" do
      assert %EncodeError{term: {1}, location: ["a", 1, "b"]} =
               error = build_error(%{"a" => [1, %{"b" => {1}}]})

      assert Exception.message(error) == ~s{cannot encode tuple (at ["a", 1, "b"])}
    end

    test "a top-level error has no location" do
      assert %EncodeError{location: []} = error = build_error({1, 2})
      assert Exception.message(error) == "cannot encode tuple"
    end

    test "a bad key's location is the map that holds it" do
      assert %EncodeError{cause: :invalid_key, term: {1}, location: ["a"]} =
               build_error(%{"a" => %{{1} => 2}})
    end

    test "an improper list's location is the list" do
      assert %EncodeError{term: 2, location: ["l"]} = build_error(%{"l" => [1 | 2]})
    end
  end

  describe "matches decode" do
    test "builds the same AST as decode, ignoring line and column" do
      yaml = "a:\n  b: [1, x]\nc: ~\nd: 1.5\n"
      term = %{"a" => %{"b" => [1, "x"]}, "c" => nil, "d" => 1.5}

      assert {:ok, %Document{root: decoded}} =
               YAML.decode(yaml, detailed: true, return: :first_document)

      assert strip_position(decoded) == root(term)
    end
  end

  defp strip_position(%Mapping{pairs: pairs} = node) do
    pairs = Enum.map(pairs, fn {key, value} -> {strip_position(key), strip_position(value)} end)
    %{node | pairs: pairs, meta: %{node.meta | line: nil, column: nil}}
  end

  defp strip_position(%List{items: items} = node) do
    %{
      node
      | items: Enum.map(items, &strip_position/1),
        meta: %{node.meta | line: nil, column: nil}
    }
  end

  defp strip_position(%Scalar{} = node), do: %{node | meta: %{node.meta | line: nil, column: nil}}
end
