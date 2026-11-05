defmodule YAML.EncodeTest do
  use ExUnit.Case, async: true

  alias YAML.{Encode, EncodeError}
  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}

  defp emit(term) do
    assert {:ok, iodata} = Encode.data(term)
    IO.iodata_to_binary(iodata)
  end

  defp emit_node(node) do
    assert {:ok, iodata} = Encode.node(node)
    IO.iodata_to_binary(iodata)
  end

  defp encode_error(term) do
    assert {:error, %EncodeError{} = error} = Encode.data(term)
    error
  end

  defp emit_decoded(yaml) do
    assert {:ok, %Document{root: root}} =
             YAML.decode(yaml, detailed: true, return: :first_document)

    emit_node(root)
  end

  defp decode(yaml, schema) do
    YAML.decode(yaml, return: :first_document, yamerl_opts: [schema: schema])
  end

  describe "scalars" do
    test "nil, booleans, integers and floats" do
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
        assert emit(term) == yaml
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
        5.0e-324
      ]

      for scalar <- scalars, schema <- [:core, :yaml11] do
        assert decode(emit(scalar), schema) == {:ok, scalar}
      end
    end

    test "infinity and NaN from decoded YAML" do
      for yaml <- [".inf", "-.inf", ".nan"] do
        assert emit_decoded(yaml) == yaml
      end
    end

    test "tags outside the core set are written by their Elixir type" do
      assert emit_decoded("!!binary aGVsbG8=") == "hello"
    end

    test "unsupported scalar values return an error" do
      node = %Scalar{value: {1, 2}, meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str"}}
      assert {:error, %EncodeError{cause: :unsupported_type, term: {1, 2}}} = Encode.node(node)
    end

    test "scalars without meta are written by their Elixir type" do
      assert {:ok, "1"} = Encode.node(%Scalar{value: 1, meta: nil})
      assert {:ok, ".inf"} = Encode.node(%Scalar{value: :"+inf", meta: nil})
    end

    test "infinity and NaN atoms are floats, as decode returns them" do
      for {atom, yaml} <- [{:"+inf", ".inf"}, {:"-inf", "-.inf"}, {:nan, ".nan"}] do
        assert emit(atom) == yaml
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
        assert emit(term) == yaml
      end
    end

    test "DateTime keeps its offset" do
      datetime = %{
        ~U[2026-10-14 15:00:00Z]
        | utc_offset: 18_000,
          time_zone: "Asia/Karachi",
          zone_abbr: "PKT"
      }

      assert emit(datetime) == ~s("2026-10-14T15:00:00+05:00")
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
        error = encode_error(term)
        assert error.cause == :unsupported_type
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
        assert emit(string) == string
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
        assert emit(string) == ~s("#{string}")
      end
    end

    test "special characters are escaped" do
      for {string, yaml} <- [
            {"a\nb", ~S("a\nb")},
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
        assert emit(string) == yaml
      end
    end

    test "atoms are written as strings" do
      assert emit(:ok) == "ok"
      assert emit(:yes) == ~s("yes")
    end

    test "invalid UTF-8 returns an error" do
      node = %Scalar{value: <<255, 104>>, meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str"}}

      assert {:error, %EncodeError{cause: :invalid_utf8, term: <<255, 104>>}} =
               Encode.node(node)
    end

    test "invalid UTF-8 in plain data returns an error" do
      for string <- [<<255>>, <<"hello", 255>>, <<"1", 255>>] do
        assert {:error, %EncodeError{cause: :invalid_utf8, term: ^string}} = Encode.data(string)
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
        "\uFEFFbom",
        "\uFFFE"
      ]

      for string <- strings, schema <- [:core, :yaml11] do
        assert decode(emit(string), schema) == {:ok, string}
      end
    end
  end

  describe "maps" do
    test "flat and nested maps" do
      assert emit(%{"a" => 1, "b" => "x"}) == "a: 1\nb: x\n"
      assert emit(%{"a" => %{"b" => %{"c" => nil}}}) == "a:\n  b:\n    c: null\n"
      assert emit(%{"a" => %{"b" => 1}, "c" => 2}) == "a:\n  b: 1\nc: 2\n"
    end

    test "empty values and empty top-level map" do
      assert emit(%{"a" => %{}, "b" => []}) == "a: {}\nb: []\n"
      assert emit(%{}) == "{}"
    end

    test "keys use the string rules" do
      assert emit(%{"a: b" => 1}) == ~s("a: b": 1\n)
      assert emit(%{"yes" => 1}) == ~s("yes": 1\n)
      assert emit(%{1 => "x"}) == "1: x\n"
      assert emit(%{nil => "x"}) == "null: x\n"
    end

    test "a \"<<\" key is tagged as a string" do
      value = %{"<<" => %{"a" => 1}, "b" => 2}
      assert emit(value) == ~s(!!str "<<":\n  a: 1\nb: 2\n)
      assert emit(%{"<<": 1}) == ~s(!!str "<<": 1\n)
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

    test "a top-level error has no location" do
      assert {:error, %EncodeError{location: []}} = Encode.data(<<255>>)
    end

    test "strings, atoms, numbers, nil and booleans are allowed as keys" do
      for {key, yaml} <- [
            {"a", "a: 1\n"},
            {:a, "a: 1\n"},
            {1, "1: 1\n"},
            {1.5, "1.5: 1\n"},
            {nil, "null: 1\n"},
            {true, "true: 1\n"}
          ] do
        assert emit(%{key => 1}) == yaml
      end
    end

    test "an atom key and a string key with the same text return a duplicate_key error" do
      assert {:error, %EncodeError{} = error} =
               Encode.data(%{"user" => %{:name => 1, "name" => 2}})

      assert error.cause == :duplicate_key
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
        assert error.cause == :invalid_key
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

    test "nested errors are returned with their location" do
      assert {:error, %EncodeError{term: {1}, location: ["a", 1, "b"]} = error} =
               Encode.data(%{"a" => [1, %{"b" => {1}}]})

      assert Exception.message(error) == ~s{cannot encode tuple (at ["a", 1, "b"])}
    end

    test "a key longer than 1024 characters is written as an explicit key" do
      long = String.duplicate("k", 1100)

      for {value, yaml} <- [
            {%{long => 1}, "? #{long}\n: 1\n"},
            {%{long => %{"a" => 1}}, "? #{long}\n:\n  a: 1\n"},
            {%{"a" => %{long => [1]}}, "a:\n  ? #{long}\n  :\n    - 1\n"},
            {[%{long => 1}], "- ? #{long}\n  : 1\n"}
          ] do
        assert emit(value) == yaml

        for schema <- [:core, :yaml11] do
          assert decode(yaml, schema) == {:ok, value}
        end
      end
    end

    test "the 1024-character limit counts quotes and escapes" do
      plain = String.duplicate("k", 1024)
      assert emit(%{plain => 1}) == "#{plain}: 1\n"

      quoted = "-" <> String.duplicate("k", 1022)
      assert emit(%{quoted => 1}) == ~s(? "#{quoted}"\n: 1\n)
    end

    test "a bad key is reported before a bad value" do
      assert {:error, %EncodeError{cause: :invalid_utf8, location: []}} =
               Encode.data(%{<<255>> => {1}})
    end

    test "infinity and NaN atom keys are not duplicates of their names" do
      value = %{:"+inf" => 1, "+inf" => 2, :nan => 3, "nan" => 4}
      assert decode(emit(value), :core) == {:ok, value}
    end

    test "dates can be keys" do
      assert emit(%{~D[2026-01-02] => 1}) == ~s("2026-01-02": 1\n)
    end

    test "decoded maps and lists are written back" do
      long = String.duplicate("k", 1100)

      for yaml <- [
            "a:\n  b: 1\n  c:\n    - x\n    - z\n",
            "- a: 1\n  b: 2\n- - 1\n  - 2\n",
            "a: {}\nb: []\n",
            "? #{long}\n: 1\n"
          ] do
        assert emit_decoded(yaml) == yaml
      end
    end

    test "AST keys follow the same rules as plain keys" do
      value = %Scalar{value: 1, meta: %Meta{tag: "tag:yaml.org,2002:int"}}
      key = %Scalar{value: {1}, meta: %Meta{tag: "tag:yaml.org,2002:str"}}
      node = %Mapping{pairs: [{key, value}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

      assert {:error,
              %EncodeError{cause: :invalid_key, message: "cannot encode tuple as a map key"}} =
               Encode.node(node)
    end

    test "malformed AST nodes return an error" do
      scalar = %Scalar{value: 1, meta: %Meta{tag: "tag:yaml.org,2002:int"}}
      seq = %Meta{tag: "tag:yaml.org,2002:seq"}
      map = %Meta{tag: "tag:yaml.org,2002:map"}

      for node <- [
            %List{items: [scalar | :x], meta: seq, length: 1},
            %List{items: :x, meta: seq, length: 0},
            %Mapping{pairs: :x, meta: map},
            %Mapping{pairs: [:x], meta: map},
            %Mapping{pairs: [{scalar, scalar} | :x], meta: map}
          ] do
        assert {:error, %EncodeError{cause: :unsupported_type}} = Encode.node(node)
      end
    end

    test "a bad key's location is the map that holds it" do
      assert {:error, %EncodeError{cause: :invalid_key, term: {1}, location: ["a"]}} =
               Encode.data(%{"a" => %{{1} => 2}})
    end

    test "map and list keys in an AST use the explicit \"? key\" form" do
      yaml = "? - a\n: 1\n? b: 2\n: 3\n"
      {:ok, [%{root: node}]} = YAML.Parser.parse(yaml, [])
      assert IO.iodata_to_binary(elem(Encode.node(node), 1)) == yaml
    end

    test "map keys, invalid keys and invalid values in an AST return errors" do
      value = %Scalar{value: 1, meta: %Meta{tag: "tag:yaml.org,2002:int"}}

      for {key, message} <- [{:junk, "cannot encode invalid AST node as a map key"}] do
        node = %Mapping{pairs: [{key, value}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}
        assert {:error, %EncodeError{cause: :invalid_key, message: ^message}} = Encode.node(node)
      end

      key = %Scalar{value: "a", meta: %Meta{tag: "tag:yaml.org,2002:str"}}
      node = %Mapping{pairs: [{key, :junk}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

      assert {:error, %EncodeError{message: "cannot encode invalid AST node", location: ["a"]}} =
               Encode.node(node)
    end
  end

  describe "lists" do
    test "improper lists return an error with the bad tail" do
      assert {:error, %EncodeError{} = error} = Encode.data([1 | 2])
      assert error.cause == :unsupported_type
      assert error.term == 2
      assert error.message == "cannot encode improper list"
    end

    test "an improper list's location is the list" do
      assert {:error, %EncodeError{term: 2, location: ["l"]}} = Encode.data(%{"l" => [1 | 2]})
    end

    test "flat and nested lists" do
      assert emit([1, "a"]) == "- 1\n- a\n"
      assert emit([[1, 2], 3]) == "- - 1\n  - 2\n- 3\n"
      assert emit([[[[1]]]]) == "- - - - 1\n"
    end

    test "empty items and empty top-level list" do
      assert emit([%{}, []]) == "- {}\n- []\n"
      assert emit([]) == "[]"
    end

    test "a list under a key is indented" do
      assert emit(%{"tags" => ["a", "b"]}) == "tags:\n  - a\n  - b\n"
    end

    test "a map in a list starts on the dash line" do
      assert emit([%{"name" => "a", "port" => 80}, %{"name" => "b"}]) ==
               "- name: a\n  port: 80\n- name: b\n"
    end

    test "mixed nesting" do
      assert emit(%{"a" => [%{"b" => [1, %{"c" => "x"}]}, ["z"]]}) ==
               "a:\n  - b:\n      - 1\n      - c: x\n  - - z\n"
    end
  end

  describe "indentation" do
    test "deeply nested single-item lists" do
      value = Enum.reduce(1..50_000, "leaf", fn _, acc -> [acc] end)
      assert emit(value) == String.duplicate("- ", 50_000) <> "leaf\n"
    end

    test "nesting deeper than the precomputed levels" do
      deep = Enum.reduce(1..40, "leaf", fn i, acc -> %{"k#{i}" => acc} end)
      lines = deep |> emit() |> String.split("\n", trim: true)

      assert length(lines) == 40
      assert Enum.at(lines, -1) == String.duplicate("  ", 39) <> "k1: leaf"
    end

    test "lists nested deeper than the precomputed levels" do
      deep = Enum.reduce(1..40, 1, fn i, acc -> [%{"k#{i}" => acc, "z" => i}] end)

      for schema <- [:core, :yaml11] do
        assert decode(emit(deep), schema) == {:ok, deep}
      end
    end
  end

  describe "maps and lists round trip" do
    test "decode back unchanged in both schemas" do
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
end
