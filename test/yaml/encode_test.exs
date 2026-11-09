defmodule YAML.EncodeTest do
  use ExUnit.Case, async: true

  alias YAML.{Encode, EncodeError}
  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}

  defp output(%Document{} = document), do: binary(Encode.document(document))
  defp output([%Document{} | _] = documents), do: binary(Encode.documents(documents))
  defp output(term), do: binary(Encode.data(term))

  defp binary({:ok, iodata}), do: IO.iodata_to_binary(iodata)

  # The output without its leading "---\n"
  defp emit(term) do
    assert "---\n" <> body = output(term)
    body
  end

  defp detailed(yaml) do
    assert {:ok, documents} = YAML.decode(yaml, detailed: true, return: :all_documents)
    documents
  end

  defp encode_error(term) do
    assert {:error, %EncodeError{} = error} = Encode.data(term)
    error
  end

  defp emit_decoded(yaml) do
    assert {:ok, %Document{} = document} =
             YAML.decode(yaml, detailed: true, return: :first_document)

    emit(document)
  end

  defp decode(yaml, schema) do
    YAML.decode(yaml, return: :first_document, schema: schema)
  end

  describe "scalars" do
    test "writes nil, booleans, integers and floats" do
      for {term, yaml} <- [
            {nil, "null"},
            {true, "true"},
            {false, "false"},
            {42, "42"},
            {-7, "-7"},
            {1.5, "1.5"},
            {1.0e20, "1.0e+20"},
            {1.0e-5, "1.0e-5"},
            {123_456_789_012_345_678_901_234_567_890, "123456789012345678901234567890"}
          ] do
        assert emit(term) == yaml <> "\n"
      end
    end

    test "every scalar reads back unchanged in both schemas" do
      scalars = [
        nil,
        true,
        false,
        0,
        -7,
        123_456_789_012_345_678_901_234_567_890,
        1.5,
        -0.25,
        1.0e15,
        1.0e20,
        -1.5e17,
        1.0e-5,
        1.7976931348623157e308,
        -0.0,
        5.0e-324,
        1.0e16,
        1.0e22
      ]

      # === tells -0.0 from 0.0
      for scalar <- scalars, schema <- [:core, :yaml11] do
        assert {:ok, decoded} = decode(emit(scalar), schema)
        assert decoded === scalar
      end
    end

    test "writes infinity and NaN from decoded YAML" do
      for yaml <- [".inf", "-.inf", ".nan"] do
        assert emit_decoded(yaml) == yaml <> "\n"
      end
    end

    test "tags outside the core set are written by their Elixir type" do
      assert emit_decoded("!!binary aGVsbG8=") == "hello\n"
    end

    test "unsupported scalar values return an error" do
      node = %Scalar{value: {1, 2}, meta: %Meta{tag: "tag:yaml.org,2002:str"}}

      assert {:error, %EncodeError{type: :unsupported_type, term: {1, 2}}} =
               Encode.document(%Document{root: node})
    end

    test "scalars without meta are written by their Elixir type" do
      assert output(%Document{root: %Scalar{value: 1, meta: nil}}) == "---\n1\n"
      assert output(%Document{root: %Scalar{value: :"+inf", meta: nil}}) == "---\n.inf\n"
    end

    test "infinity and NaN atoms are floats, as decode returns them" do
      for {atom, yaml} <- [{:"+inf", ".inf"}, {:"-inf", "-.inf"}, {:nan, ".nan"}] do
        assert emit(atom) == yaml <> "\n"
      end
    end
  end

  describe "dates and times" do
    test "are written as ISO 8601 text" do
      for {term, yaml} <- [
            {~D[2026-10-14], ~s("2026-10-14")},
            {~T[10:00:00], ~s("10:00:00")},
            {~N[2026-10-14 10:00:00], ~s("2026-10-14T10:00:00")},
            {~U[2026-10-14 10:00:00Z], ~s("2026-10-14T10:00:00Z")}
          ] do
        assert emit(term) == yaml <> "\n"
      end
    end

    test "DateTime keeps its offset" do
      datetime = %{
        ~U[2026-10-14 15:00:00Z]
        | utc_offset: 18_000,
          time_zone: "Asia/Karachi",
          zone_abbr: "PKT"
      }

      assert emit(datetime) == ~s("2026-10-14T15:00:00+05:00"\n)
    end
  end

  describe "unsupported values" do
    test "return an unsupported_type error" do
      for {term, type} <- [
            {{1, 2}, "tuple"},
            {self(), "pid"},
            {make_ref(), "reference"},
            {&IO.puts/1, "function"},
            {%URI{}, "URI struct without a YAML.Encoder"},
            {<<1::3>>, "bitstring"}
          ] do
        error = encode_error(term)
        assert error.type == :unsupported_type
        assert error.term == term
        assert error.message == "cannot encode #{type}"
      end
    end

    test "a top-level error has no location" do
      assert %EncodeError{location: []} = error = encode_error({1, 2})
      assert Exception.message(error) == "cannot encode tuple"
    end
  end

  describe "strings" do
    test "safe strings are written plain" do
      for string <- ["hello", "hello world", "a:b", "a#b", "truth", "quote\"in", "日本語"] do
        assert emit(string) == string <> "\n"
      end
    end

    test "strings that would read as something else are quoted" do
      for string <- [
            "",
            "true",
            "yes",
            "NO",
            "tRuE",
            "nULL",
            "yEs",
            "oFf",
            "null",
            "~",
            "<<",
            "123",
            "-1",
            "1.5",
            ".inf",
            "12:30",
            "2026-10-14",
            "-x",
            "#x",
            "%x",
            "_",
            "_1",
            "=",
            "a: b",
            "a #b",
            "x:",
            " x",
            "x "
          ] do
        assert emit(string) == ~s("#{string}"\n)
      end
    end

    test "special characters are escaped" do
      for {string, yaml} <- [
            {"abc\n", ~S("abc\n")},
            {"a\tb", ~S("a\tb")},
            {"a\r\nb", ~S("a\r\nb")},
            {"back\\slash\n", ~S("back\\slash\n")},
            {"say \"hi\"\n", ~S("say \"hi\"\n")},
            {"bell\a", ~S("bell\x07")},
            {"a\x7Fb", ~S("a\x7Fb")},
            {"é\n", ~S("é\n")},
            {"😀\n", ~S("😀\n")},
            {"a\u0085b", ~S("a\Nb")},
            {"a\u2028b", ~S("a\Lb")},
            {"a\u2029b", ~S("a\Pb")},
            {"c1\u0090x", ~S("c1\x90x")},
            {"\uFEFFbom", ~S("\uFEFFbom")},
            {"\uFFFE", ~S("\uFFFE")}
          ] do
        assert emit(string) == yaml <> "\n"
      end
    end

    test "atoms are written as strings" do
      assert emit(:ok) == "ok\n"
      assert emit(:yes) == ~s("yes"\n)
    end

    test "invalid UTF-8 returns an error" do
      node = %Scalar{value: <<255, 104>>, meta: %Meta{tag: "tag:yaml.org,2002:str"}}

      assert {:error, %EncodeError{type: :invalid_utf8, term: <<255, 104>>}} =
               Encode.document(%Document{root: node})
    end

    test "invalid UTF-8 in plain data returns an error" do
      for string <- [
            <<255>>,
            <<"hello", 255>>,
            <<"1", 255>>,
            <<0xED, 0xA0, 0x80>>,
            <<0xC0, 0x80>>
          ] do
        assert {:error, %EncodeError{type: :invalid_utf8, term: ^string}} = Encode.data(string)
      end
    end

    test "every string reads back unchanged in both schemas" do
      strings = [
        "hello",
        "",
        "true",
        "True",
        "tRuE",
        "yes",
        "on",
        "Off",
        "y",
        "N",
        "NULL",
        "<<",
        "=",
        "_",
        "__",
        "_1",
        "123",
        "+1",
        "0x1F",
        "1_000",
        "12:30",
        "10:00:00",
        "a: b",
        "a #b",
        "- x",
        "{x",
        "[x",
        "!x",
        "*x",
        "|x",
        "'x",
        "\"x",
        "%x",
        "@x",
        "`x",
        ",x",
        "?x",
        ":x",
        " x",
        "x ",
        " ",
        "\t",
        "a:\tb",
        "---",
        "...",
        "a\nb",
        "bell\a",
        "nul\0",
        "a\x7Fb",
        "ünïcødé",
        "emoji 😀",
        "😀\n",
        "a\u2028b",
        "a\u2029b",
        "a\u0085b",
        "c1\u0090x",
        "\uFEFFbom",
        "\uFFFE",
        "\uFFFF",
        String.duplicate("long \"text\"\n", 10_000)
      ]

      for string <- strings, schema <- [:core, :yaml11] do
        assert decode(emit(string), schema) == {:ok, string}
      end
    end
  end

  describe "maps" do
    test "writes flat and nested maps" do
      assert emit(%{"a" => 1, "b" => "x"}) == "a: 1\nb: x\n"
      assert emit(%{"a" => %{"b" => %{"c" => nil}}}) == "a:\n  b:\n    c: null\n"
      assert emit(%{"a" => %{"b" => 1}, "c" => 2}) == "a:\n  b: 1\nc: 2\n"
    end

    test "writes empty values and an empty top-level map" do
      assert emit(%{"a" => %{}, "b" => []}) == "a: {}\nb: []\n"
      assert emit(%{}) == "{}\n"
    end

    test "keys use the string rules" do
      assert emit(%{"a: b" => 1}) == ~s("a: b": 1\n)
      assert emit(%{"yes" => 1}) == ~s("yes": 1\n)
      assert emit(%{1 => "x"}) == "1: x\n"
      assert emit(%{nil => "x"}) == "null: x\n"
    end

    test "a \"<<\" key is quoted" do
      value = %{"<<" => %{"a" => 1}, "b" => 2}
      assert emit(value) == ~s("<<":\n  a: 1\nb: 2\n)
      assert emit(%{"<<": 1}) == ~s("<<": 1\n)
      assert emit(["<<"]) == ~s(- "<<"\n)

      assert YAML.decode(emit(value), enable_merge: false, return: :first_document) ==
               {:ok, value}
    end

    test "errors from nested values report their location" do
      for {value, location} <- [
            {%{"a" => [%{"b" => <<255>>}]}, ["a", 0, "b"]},
            {%{"files" => [<<1>>, <<0xFF>>]}, ["files", 1]},
            {%{"a" => %{<<255>> => 1}}, ["a"]}
          ] do
        assert {:error, %EncodeError{location: ^location} = error} = Encode.data(value)

        assert Exception.message(error) ==
                 "cannot encode invalid UTF-8 string (at #{inspect(location)})"
      end
    end

    test "an invalid string at the top has no location" do
      assert {:error, %EncodeError{location: []}} = Encode.data(<<255>>)
    end

    test "strings, atoms, numbers, nil, booleans and dates are allowed as keys" do
      for {key, yaml} <- [
            {"a", "a: 1\n"},
            {:a, "a: 1\n"},
            {1, "1: 1\n"},
            {1.5, "1.5: 1\n"},
            {nil, "null: 1\n"},
            {true, "true: 1\n"},
            {~D[2026-01-02], ~s("2026-01-02": 1\n)}
          ] do
        assert emit(%{key => 1}) == yaml
      end
    end

    test "an atom key and a string key with the same text return a duplicate_key error" do
      assert {:error, %EncodeError{} = error} =
               Encode.data(%{"user" => %{:name => 1, "name" => 2}})

      assert error.type == :duplicate_key
      assert error.term == :name
      assert error.location == ["user"]
      assert Exception.message(error) == ~s{duplicate map key "name" (at ["user"])}
    end

    test "keys that are written differently are not duplicates" do
      value = %{
        :a => 1,
        "b" => 2,
        1 => 3,
        "1" => 4,
        nil => 5,
        "null" => 6,
        true => 7,
        "true" => 8
      }

      for schema <- [:core, :yaml11] do
        assert decode(emit(value), schema) ==
                 {:ok,
                  %{
                    "a" => 1,
                    "b" => 2,
                    1 => 3,
                    "1" => 4,
                    nil => 5,
                    "null" => 6,
                    true => 7,
                    "true" => 8
                  }}
      end
    end

    test "other keys return an invalid_key error" do
      for {key, type} <- [{{1, 2}, "tuple"}, {self(), "pid"}, {URI.parse("x"), "URI struct"}] do
        assert {:error, %EncodeError{} = error} = Encode.data(%{key => 1})
        assert error.type == :invalid_key
        assert error.term == key
        assert error.message == "cannot encode #{type} as a map key"
      end
    end

    test "map and list keys use the explicit \"? key\" form" do
      for {value, yaml} <- [
            {%{["a", "b"] => 1}, "? - a\n  - b\n: 1\n"},
            {%{%{"a" => 1} => [2]}, "? a: 1\n:\n  - 2\n"},
            {%{[] => 1, %{} => 2}, "? {}\n: 2\n? []\n: 1\n"},
            {[%{["a"] => 1, "b" => 2}], "- ? - a\n  : 1\n  b: 2\n"},
            {%{"x" => %{[1] => %{"z" => 2}}}, "x:\n  ? - 1\n  :\n    z: 2\n"}
          ] do
        assert emit(value) == yaml
        assert YAML.decode(yaml, return: :first_document) == {:ok, value}
      end
    end

    test "a map key that starts with a \"? key\" is written in flow style" do
      for {value, yaml} <- [
            {%{%{[1] => 2} => 3}, "? {[1]: 2}\n: 3\n"},
            {%{%{%{"a" => 1} => "b,c"} => [1]}, ~s(? {{"a": 1}: "b,c"}\n:\n  - 1\n)},
            {%{%{[] => %{}, "a" => [nil, 1.5]} => 1}, ~s(? {[]: {}, "a": [null, 1.5]}\n: 1\n)},
            {%{"x" => [%{%{["<<"] => "y"} => 1}]}, ~s(x:\n  - ? {["<<"]: "y"}\n    : 1\n)}
          ] do
        assert emit(value) == yaml
        assert decode(yaml, :core) == {:ok, value}
      end
    end

    test "a map key that starts with a plain key keeps the block form" do
      assert emit(%{%{1 => 1, [1] => 2} => 3}) == "? 1: 1\n  ? - 1\n  : 2\n: 3\n"
    end

    test "errors inside a map or list key start with that key" do
      for {value, location} <- [
            {%{["k", <<255>>] => 1}, [["k", <<255>>], 1]},
            {%{"a" => %{%{"b" => {1}} => 1}}, ["a", %{"b" => {1}}, "b"]},
            {%{%{[1] => {1}} => 1}, [%{[1] => {1}}, [1]]}
          ] do
        assert {:error, %EncodeError{location: ^location}} = Encode.data(value)
      end
    end

    test "nested errors are returned with their location" do
      assert {:error, %EncodeError{term: {1}, location: ["a", 1, "b"]} = error} =
               Encode.data(%{"a" => [1, %{"b" => {1}}]})

      assert Exception.message(error) == ~s{cannot encode tuple (at ["a", 1, "b"])}
    end

    test "a key longer than 1024 characters is written as an explicit key" do
      long = String.duplicate("k", 1100)

      for {value, yaml} <- [
            {%{long => 1}, "? #{long}\n: 1\n"},
            {%{"a" => %{long => [1]}}, "a:\n  ? #{long}\n  :\n    - 1\n"},
            {[%{long => 1}], "- ? #{long}\n  : 1\n"}
          ] do
        assert emit(value) == yaml
        assert decode(yaml, :core) == {:ok, value}
      end

      assert emit(%{String.duplicate("k", 1024) => 1}) == String.duplicate("k", 1024) <> ": 1\n"
    end

    test "a bad key is reported before a bad value" do
      assert {:error, %EncodeError{type: :invalid_utf8, location: []}} =
               Encode.data(%{<<255>> => {1}})
    end

    test "infinity and NaN atom keys are not duplicates of their names" do
      value = %{:"+inf" => 1, "+inf" => 2, :nan => 3, "nan" => 4}
      assert decode(emit(value), :core) == {:ok, value}
    end

    test "a date or time key and a string key with the same text return a duplicate_key error" do
      for key <- [~D[2026-01-02], ~T[10:00:00], ~N[2026-01-02 10:00:00], ~U[2026-01-02 10:00:00Z]] do
        text = to_string(key) |> String.replace(" ", "T")

        assert {:error, %EncodeError{type: :duplicate_key, term: ^key}} =
                 Encode.data(%{key => 1, text => 2})
      end
    end

    test "a bad key's location is the map that holds it" do
      assert {:error, %EncodeError{type: :invalid_key, term: {1}, location: ["a"]}} =
               Encode.data(%{"a" => %{{1} => 2}})
    end
  end

  describe "AST" do
    test "decoded maps and lists are written back" do
      for yaml <- [
            "a:\n  b: 1\n  c:\n    - x\n    - z\n",
            "- a: 1\n  b: 2\n- - 1\n  - 2\n",
            "a: {}\nb: []\n"
          ] do
        assert emit_decoded(yaml) == yaml
      end
    end

    test "map and list keys in an AST use the explicit \"? key\" form" do
      yaml = "? - a\n: 1\n? b: 2\n: 3\n"
      {:ok, [document]} = YAML.Parser.parse(yaml)
      assert IO.iodata_to_binary(elem(Encode.document(document), 1)) == "---\n" <> yaml
    end

    test "a map key in an AST that starts with a \"? key\" is written in flow style" do
      {:ok, [document]} = YAML.Parser.parse("? {[1]: 2}\n: 3\n")
      assert IO.iodata_to_binary(elem(Encode.document(document), 1)) == "---\n? {[1]: 2}\n: 3\n"
    end
  end

  describe "lists" do
    test "writes flat and nested lists" do
      assert emit([1, "a"]) == "- 1\n- a\n"
      assert emit([[1, 2], 3]) == "- - 1\n  - 2\n- 3\n"
      assert emit([[[[1]]]]) == "- - - - 1\n"
    end

    test "writes empty items and an empty top-level list" do
      assert emit([%{}, []]) == "- {}\n- []\n"
      assert emit([]) == "[]\n"
    end

    test "a list under a key is indented" do
      assert emit(%{"tags" => ["a", "b"]}) == "tags:\n  - a\n  - b\n"
    end

    test "a map in a list starts on the dash line" do
      assert emit([%{"name" => "a", "port" => 80}, %{"name" => "b"}]) ==
               "- name: a\n  port: 80\n- name: b\n"
    end

    test "writes mixed nesting" do
      assert emit(%{"a" => [%{"b" => [1, %{"c" => "x"}]}, ["z"]]}) ==
               "a:\n  - b:\n      - 1\n      - c: x\n  - - z\n"
    end
  end

  describe "indentation" do
    test "writes deeply nested single-item lists" do
      value = Enum.reduce(1..50_000, "leaf", fn _, acc -> [acc] end)
      assert emit(value) == String.duplicate("- ", 50_000) <> "leaf\n"
    end

    test "writes nesting deeper than the precomputed levels" do
      deep = Enum.reduce(1..40, "leaf", fn i, acc -> %{"k#{i}" => acc} end)
      lines = deep |> emit() |> String.split("\n", trim: true)

      assert length(lines) == 40
      assert Enum.at(lines, -1) == String.duplicate("  ", 39) <> "k1: leaf"
    end

    test "writes lists nested deeper than the precomputed levels" do
      deep = Enum.reduce(1..40, 1, fn i, acc -> [%{"k#{i}" => acc, "z" => i}] end)

      for schema <- [:core, :yaml11] do
        assert decode(emit(deep), schema) == {:ok, deep}
      end
    end
  end

  describe "maps and lists round trip" do
    test "maps and lists decode back unchanged in both schemas" do
      values = [
        %{"a" => 1, "b" => %{"c" => [1, 2]}},
        [%{"name" => "a", "ports" => [80, 443]}, [], %{}],
        %{"servers" => [%{"env" => %{"k" => "v"}, "host" => "x"}], "empty" => [[], [[]]]},
        %{"a" => [%{"b" => [1, %{"c" => "x"}]}, ["y"]]},
        %{1 => "a", 1.5 => "b", true => "c", nil => "d"},
        %{"" => 1, "a: b" => 2, "a:" => 3, "#x" => 4}
      ]

      for value <- values, schema <- [:core, :yaml11] do
        assert decode(emit(value), schema) == {:ok, value}
      end
    end
  end

  describe "multi-line strings" do
    test "chomping indicator follows the final newlines" do
      assert emit(%{"s" => "a\nb\n"}) == "s: |\n  a\n  b\n"
      assert emit(%{"s" => "a\nb"}) == "s: |-\n  a\n  b\n"
      assert emit(%{"s" => "a\nb\n\n"}) == "s: |+\n  a\n  b\n\n"
    end

    test "lines are kept exactly" do
      assert emit(%{"s" => "a\n\nb\n"}) == "s: |\n  a\n\n  b\n"
      assert emit(%{"s" => "a\n   \nb\n"}) == "s: |\n  a\n     \n  b\n"
      assert emit(%{"s" => "# not a comment\n- x\n"}) == "s: |\n  # not a comment\n  - x\n"
    end

    test "are written in list items and nested maps" do
      assert emit(["a\nb\n"]) == "- |\n  a\n  b\n"

      assert emit(%{"jobs" => [%{"run" => "one\ntwo\n"}]}) ==
               "jobs:\n  - run: |\n      one\n      two\n"
    end

    test "falls back to quotes when a block can't hold the text" do
      for {string, quoted} <- [
            {" a\nb\n", ~S(" a\nb\n")},
            {"\n x\ny", ~S("\n x\ny")},
            {"\n\n  a\nb", ~S("\n\n  a\nb")},
            {"\ta\nb", ~S("\ta\nb")},
            {"\n\ta\nb", ~S("\n\ta\nb")},
            {"abc\n", ~S("abc\n")},
            {"a\r\nb\n", ~S("a\r\nb\n")},
            {"a\nb\u2028c\n", ~S("a\nb\Lc\n")},
            {"a\nb\u0085c", ~S("a\nb\Nc")},
            {"a\nb\uFEFF", ~S("a\nb\uFEFF")},
            {"a\rb\nc", ~S("a\rb\nc")},
            {"\n\n", ~S("\n\n")}
          ] do
        assert emit(%{"s" => string}) == "s: " <> quoted <> "\n"
      end
    end

    test "decoded blocks are written back" do
      for yaml <- ["s: |\n  a\n  b\n", "- |-\n  a\n  b\n- x\n", "a:\n  b: |+\n    x\n    y\n\n"] do
        assert emit_decoded(yaml) == yaml
      end
    end

    test "atoms with a newline are written like strings" do
      assert emit(%{"s" => :"a\nb\n"}) == "s: |\n  a\n  b\n"
    end

    test "writes AST blocks in nested maps and lists" do
      text = fn value -> %Scalar{value: value, meta: %Meta{tag: "tag:yaml.org,2002:str"}} end
      list = %List{items: [text.("a\nb\n")], meta: %Meta{tag: "tag:yaml.org,2002:seq"}, length: 1}
      inner = %Mapping{pairs: [{text.("s"), text.("x\ny")}, {text.("l"), list}], meta: %Meta{}}
      node = %Mapping{pairs: [{text.("m"), inner}], meta: %Meta{}}

      assert emit(%Document{root: node}) ==
               "m:\n  s: |-\n    x\n    y\n  l:\n    - |\n      a\n      b\n"
    end

    test "a tab after the first line stays in the block" do
      assert emit(%{"s" => "a\n\tb\n"}) == "s: |\n  a\n  \tb\n"
    end

    test "multi-line keys stay quoted" do
      assert emit(%{"a\nb" => 1}) == ~S("a\nb": 1) <> "\n"
    end

    test "invalid UTF-8 returns an error with its location" do
      assert {:error, %EncodeError{type: :invalid_utf8, location: ["s"]}} =
               Encode.data(%{"s" => <<"a\nb", 255>>})
    end

    test "multi-line strings decode back unchanged in both schemas" do
      strings = [
        "a\nb\n",
        "a\nb",
        "a\nb\n\n\n",
        "a\n\nb\n",
        "a\n   \nb\n",
        "a  \nb\n",
        "# c\n- x\nk: v\n---\n",
        "a\tb\n\tc\n",
        "\nabc\n",
        "a\n  ",
        " a\nb\n",
        "\n x\ny",
        "\n\n  a\nb",
        "a\r\nb\n",
        "\n\n",
        "a\rb\nc",
        "\tx\ny\n",
        "a\n\t\n",
        "é\n日本\n"
      ]

      for string <- strings,
          value <- [
            %{"s" => string},
            [string],
            %{"a" => [%{"s" => string}]},
            %{"s" => string, "t" => 1},
            [string, 1]
          ],
          schema <- [:core, :yaml11] do
        assert decode(emit(value), schema) == {:ok, value}
      end
    end
  end

  describe "documents" do
    test "every document starts with --- and ends with one newline" do
      for {term, yaml} <- [
            {%{"a" => 1}, "---\na: 1\n"},
            {42, "---\n42\n"},
            {"yes", ~s(---\n"yes"\n)},
            {%{}, "---\n{}\n"},
            {[], "---\n[]\n"},
            {nil, "---\nnull\n"},
            {[1, %{"b" => 2}], "---\n- 1\n- b: 2\n"}
          ] do
        assert output(term) == yaml
        assert output(hd(detailed(yaml))) == yaml
      end
    end

    test "a list of documents is written back to back" do
      yaml = "---\na: 1\n---\n42\n---\n|\n  x\n  y\n"
      assert output(detailed(yaml)) == yaml
      assert YAML.decode(yaml, return: :all_documents) == {:ok, [%{"a" => 1}, 42, "x\ny\n"]}
    end

    test "writes nothing for an empty list of documents" do
      assert {:ok, iodata} = Encode.documents([])
      assert IO.iodata_to_binary(iodata) == ""
    end

    test "top-level blocks keep their trailing newlines" do
      for {string, yaml} <- [
            {"a\nb", "---\n|-\n  a\n  b\n"},
            {"a\nb\n", "---\n|\n  a\n  b\n"},
            {"a\nb\n\n", "---\n|+\n  a\n  b\n\n"}
          ] do
        assert output(string) == yaml

        for schema <- [:core, :yaml11] do
          assert decode(yaml, schema) == {:ok, string}
        end
      end
    end

    test "writes a |+ block followed by another document" do
      yaml = "---\n|+\n  a\n  b\n\n---\n1\n"
      assert output(detailed(yaml)) == yaml
      assert YAML.decode(yaml, return: :all_documents) == {:ok, ["a\nb\n\n", 1]}
    end

    test "detailed decode of several documents round-trips" do
      yaml = "---\na: [1, 2]\n---\nx\n---\n|\n  a\n  b\n---\n{}\n"

      assert YAML.decode(output(detailed(yaml)), return: :all_documents) ==
               YAML.decode(yaml, return: :all_documents)
    end

    test "an empty document is written as null" do
      assert output(detailed("---\n")) == "---\nnull\n"
    end

    test "an error in a later document starts with its index" do
      [first, %Document{root: root} = second] = detailed("1\n---\nx\n")
      documents = [first, %{second | root: %{root | value: <<255>>}}]

      assert {:error, %EncodeError{type: :invalid_utf8, location: [1]}} =
               Encode.documents(documents)
    end

    test "the document index comes before the path inside it" do
      [first, %Document{root: %Mapping{pairs: [{key, list}]}} = second] =
        detailed("1\n---\na: [1, x]\n")

      [one, x] = list.items

      second = %{
        second
        | root: %{second.root | pairs: [{key, %{list | items: [one, %{x | value: <<255>>}]}}]}
      }

      assert {:error, %EncodeError{type: :invalid_utf8, location: [1, "a", 1]}} =
               Encode.documents([first, second])
    end
  end
end
