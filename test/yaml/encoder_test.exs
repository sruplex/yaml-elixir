defmodule YAML.EncoderTest do
  use ExUnit.Case, async: true

  alias YAML.EncodeError
  alias YAML.Support.{Point, User, Session, Money, Box, Broken}

  defp encode(term), do: YAML.encode(term, sort_maps: true)

  describe "@derive" do
    test "writes every field without options" do
      assert encode(%Point{x: 1, y: 2}) == {:ok, ~s(---\nx: 1\n"y": 2\n)}
    end

    test "writes only the fields in :only" do
      user = %User{name: "Ada", email: "ada@example.com", password: "secret"}
      assert encode(user) == {:ok, "---\nemail: ada@example.com\nname: Ada\n"}
    end

    test "leaves out the fields in :except" do
      assert encode(%Session{id: 7, user: nil, token: "secret"}) ==
               {:ok, "---\nid: 7\nuser: null\n"}
    end

    test "decodes back as a map with string keys" do
      user = %User{name: "Ada", email: "ada@example.com", password: "secret"}
      assert YAML.decode!(YAML.encode!(user)) == %{"name" => "Ada", "email" => "ada@example.com"}
    end
  end

  describe "defimpl" do
    test "writes the data the implementation returns" do
      assert encode(%Money{amount: "12.50", currency: "USD"}) == {:ok, ~s(---\n"12.50 USD"\n)}
    end

    test "returned structs are encoded through their own implementation" do
      assert encode(%Box{content: %Point{x: 0, y: 0}}) == {:ok, ~s(---\nx: 0\n"y": 0\n)}
      assert encode(%Box{content: [%Box{content: "deep"}]}) == {:ok, "---\n- deep\n"}
    end

    test "returned multi-line strings are written as block scalars" do
      assert encode(%Box{content: "a\nb\n"}) == {:ok, "---\n|\n  a\n  b\n"}
    end
  end

  describe "nested structs" do
    test "are encoded inside maps and lists" do
      data = %{
        "price" => %Money{amount: 5, currency: "EUR"},
        "points" => [%Point{x: 1, y: 2}],
        "session" => %Session{id: 1, user: %User{name: "Ada", email: "a@b.c"}, token: "t"}
      }

      assert encode(data) ==
               {:ok,
                """
                ---
                points:
                  - x: 1
                    "y": 2
                price: "5 EUR"
                session:
                  id: 1
                  user:
                    email: a@b.c
                    name: Ada
                """}
    end

    test "are encoded inside a map key" do
      assert encode(%{%{[1] => %Point{x: 1, y: 2}} => 1}) ==
               {:ok, ~s(---\n? {[1]: {"x": 1, "y": 2}}\n: 1\n)}
    end

    test "are encoded in each streamed document" do
      stream = YAML.encode_stream!([%Point{x: 1, y: 2}, %Money{amount: 3, currency: "USD"}])

      assert Enum.map(stream, &IO.iodata_to_binary/1) == [
               ~s(---\nx: 1\n"y": 2\n),
               ~s(---\n"3 USD"\n)
             ]
    end
  end

  describe "dates and times" do
    test "are written as ISO 8601 strings" do
      assert YAML.Encoder.encode(~D[2024-01-02]) == "2024-01-02"
      assert YAML.Encoder.encode(~T[10:00:00]) == "10:00:00"
      assert YAML.Encoder.encode(~N[2024-01-02 10:00:00]) == "2024-01-02T10:00:00"
      assert YAML.Encoder.encode(~U[2024-01-02 10:00:00Z]) == "2024-01-02T10:00:00Z"
    end
  end

  describe "errors" do
    test "a struct without an implementation returns an unsupported_type error" do
      assert {:error, %EncodeError{} = error} = encode(%{"a" => [%URI{}]})
      assert error.type == :unsupported_type
      assert error.term == %URI{}
      assert error.location == ["a", 0]
      assert error.message == "cannot encode URI struct without a YAML.Encoder"
    end

    test "unsupported data an implementation returns has the struct's location" do
      assert {:error, %EncodeError{message: "cannot encode tuple", location: ["a"]}} =
               encode(%{"a" => %Box{content: {1, 2}}})
    end

    test "an error raised inside an implementation is not caught" do
      assert_raise Protocol.UndefinedError, fn -> encode(%Broken{}) end
    end

    test "a struct as a map key returns an invalid_key error" do
      assert {:error, %EncodeError{type: :invalid_key}} = encode(%{%Point{x: 1, y: 2} => 1})
    end
  end
end
