defmodule YAML.EmitterTest do
  use ExUnit.Case, async: true

  alias YAML.{Builder, Emitter, EncodeError}
  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}

  # Emits a whole document and returns its body, without the leading "---\n"
  defp emit(term) do
    assert {:ok, document} = Builder.build(term)
    emit_document(document)
  end

  defp emit_document(document) do
    assert {:ok, iodata} = Emitter.document(document)
    assert "---\n" <> body = IO.iodata_to_binary(iodata)
    body
  end

  defp emit_decoded(yaml) do
    assert {:ok, %Document{} = document} =
             YAML.decode(yaml, detailed: true, return: :first_document)

    emit_document(document)
  end

  defp output(%Document{} = document) do
    assert {:ok, iodata} = Emitter.document(document)
    IO.iodata_to_binary(iodata)
  end

  defp output(documents) when is_list(documents) do
    assert {:ok, iodata} = Emitter.documents(documents)
    IO.iodata_to_binary(iodata)
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
        5.0e-324
      ]

      for scalar <- scalars, schema <- [:core, :yaml11] do
        assert decode(emit(scalar), schema) == {:ok, scalar}
      end
    end

    test "infinity and NaN from decoded YAML" do
      for yaml <- [".inf", "-.inf", ".nan"] do
        assert emit_decoded(yaml) == yaml <> "\n"
      end
    end

    test "tags outside the core set are written by their Elixir type" do
      assert emit_decoded("!!binary aGVsbG8=") == "hello\n"
    end

    test "unsupported scalar values return an error" do
      node = %Scalar{value: {1, 2}, meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str"}}

      assert {:error, %EncodeError{cause: :unsupported_type, term: {1, 2}}} =
               Emitter.document(%Document{root: node})
    end

    test "scalars without meta are written by their Elixir type" do
      assert output(%Document{root: %Scalar{value: 1, meta: nil}}) == "---\n1\n"
      assert output(%Document{root: %Scalar{value: :"+inf", meta: nil}}) == "---\n.inf\n"
    end
  end

  describe "strings" do
    test "safe strings are written plain" do
      for string <- ["hello", "hello world", "a:b", "a#b", "tRuE", "quote\"in", "日本語"] do
        assert emit(string) == string <> "\n"
      end
    end

    test "strings that would read as something else are quoted" do
      for string <- [
            "",
            "true",
            "yes",
            "NO",
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
      node = %Scalar{value: <<255, 104>>, meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str"}}

      assert {:error, %EncodeError{cause: :invalid_utf8, term: <<255, 104>>}} =
               Emitter.document(%Document{root: node})
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

      assert YAML.decode(emit(value), enable_merge: false, return: :first_document) ==
               {:ok, value}
    end

    test "errors from nested values report their location" do
      for {value, location} <- [
            {%{"a" => [%{"b" => <<255>>}]}, ["a", 0, "b"]},
            {%{"files" => [<<1>>, <<0xFF>>]}, ["files", 1]},
            {%{"a" => %{<<255>> => 1}}, ["a"]}
          ] do
        assert {:ok, document} = Builder.build(value)
        assert {:error, %EncodeError{location: ^location} = error} = Emitter.document(document)

        assert Exception.message(error) ==
                 "cannot encode invalid UTF-8 string (at #{inspect(location)})"
      end
    end

    test "a top-level error has no location" do
      assert {:ok, document} = Builder.build(<<255>>)
      assert {:error, %EncodeError{location: []}} = Emitter.document(document)
    end

    test "a non-scalar key in an AST returns an error" do
      key = %List{items: [], meta: %Meta{tag: "tag:yaml.org,2002:seq"}, length: 0}
      value = %Scalar{value: 1, meta: %Meta{tag: "tag:yaml.org,2002:int"}}
      node = %Mapping{pairs: [{key, value}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

      assert {:error,
              %EncodeError{cause: :invalid_key, message: "cannot encode list as a map key"}} =
               Emitter.document(%Document{root: node})
    end

    test "map keys, invalid keys and invalid values in an AST return errors" do
      value = %Scalar{value: 1, meta: %Meta{tag: "tag:yaml.org,2002:int"}}
      map_key = %Mapping{pairs: [], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

      for {key, message} <- [
            {map_key, "cannot encode map as a map key"},
            {:junk, "cannot encode invalid AST node as a map key"}
          ] do
        node = %Mapping{pairs: [{key, value}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

        assert {:error, %EncodeError{cause: :invalid_key, message: ^message}} =
                 Emitter.document(%Document{root: node})
      end

      key = %Scalar{value: "a", meta: %Meta{tag: "tag:yaml.org,2002:str"}}
      node = %Mapping{pairs: [{key, :junk}], meta: %Meta{tag: "tag:yaml.org,2002:map"}}

      assert {:error, %EncodeError{message: "cannot encode invalid AST node", location: ["a"]}} =
               Emitter.document(%Document{root: node})
    end
  end

  describe "lists" do
    test "flat and nested lists" do
      assert emit([1, "a"]) == "- 1\n- a\n"
      assert emit([[1, 2], 3]) == "- - 1\n  - 2\n- 3\n"
      assert emit([[[[1]]]]) == "- - - - 1\n"
    end

    test "empty items and empty top-level list" do
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

    test "mixed nesting" do
      assert emit(%{"a" => [%{"b" => [1, %{"c" => "x"}]}, ["z"]]}) ==
               "a:\n  - b:\n      - 1\n      - c: x\n  - - z\n"
    end
  end

  describe "indentation" do
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

    test "in list items and nested maps" do
      assert emit(["a\nb\n"]) == "- |\n  a\n  b\n"

      assert emit(%{"jobs" => [%{"run" => "one\ntwo\n"}]}) ==
               "jobs:\n  - run: |\n      one\n      two\n"
    end

    test "falls back to quotes when a block can't hold the text" do
      for {string, quoted} <- [
            {" a\nb\n", ~S(" a\nb\n")},
            {"\n x\ny", ~S("\n x\ny")},
            {"\n\n  a\nb", ~S("\n\n  a\nb")},
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

    test "multi-line keys stay quoted" do
      assert emit(%{"a\nb" => 1}) == ~S("a\nb": 1) <> "\n"
    end

    test "invalid UTF-8 returns an error with its location" do
      assert {:ok, document} = Builder.build(%{"s" => <<"a\nb", 255>>})

      assert {:error, %EncodeError{cause: :invalid_utf8, location: ["s"]}} =
               Emitter.document(document)
    end

    test "decode back unchanged in both schemas" do
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
        assert {:ok, document} = Builder.build(term)
        assert output(document) == yaml
      end
    end

    test "a top-level multi-line string is a block" do
      assert {:ok, document} = Builder.build("a\nb\n")
      assert output(document) == "---\n|\n  a\n  b\n"
    end

    test "a list of documents is written back to back" do
      documents =
        for term <- [%{"a" => 1}, 42, "x\ny\n"] do
          assert {:ok, document} = Builder.build(term)
          document
        end

      yaml = output(documents)
      assert yaml == "---\na: 1\n---\n42\n---\n|\n  x\n  y\n"
      assert YAML.decode(yaml, return: :all_documents) == {:ok, [%{"a" => 1}, 42, "x\ny\n"]}
    end

    test "no documents" do
      assert output([]) == ""
    end

    test "top-level blocks keep their trailing newlines" do
      for {string, yaml} <- [
            {"a\nb", "---\n|-\n  a\n  b\n"},
            {"a\nb\n", "---\n|\n  a\n  b\n"},
            {"a\nb\n\n", "---\n|+\n  a\n  b\n\n"}
          ] do
        assert {:ok, document} = Builder.build(string)
        assert output(document) == yaml

        for schema <- [:core, :yaml11] do
          assert decode(yaml, schema) == {:ok, string}
        end
      end
    end

    test "a |+ block followed by another document" do
      documents =
        for term <- ["a\nb\n\n", 1] do
          assert {:ok, document} = Builder.build(term)
          document
        end

      yaml = output(documents)
      assert yaml == "---\n|+\n  a\n  b\n\n---\n1\n"
      assert YAML.decode(yaml, return: :all_documents) == {:ok, ["a\nb\n\n", 1]}
    end

    test "detailed decode of several documents round-trips" do
      yaml = "---\na: [1, 2]\n---\nx\n---\n|\n  a\n  b\n---\n{}\n"
      assert {:ok, documents} = YAML.decode(yaml, detailed: true, return: :all_documents)

      assert YAML.decode(output(documents), return: :all_documents) ==
               YAML.decode(yaml, return: :all_documents)
    end

    test "a nil root is an error" do
      assert {:error, %EncodeError{message: "cannot encode invalid AST node", location: []}} =
               Emitter.document(%Document{root: nil})
    end

    test "an error in a later document has no document index" do
      documents =
        for term <- [1, <<255>>] do
          assert {:ok, document} = Builder.build(term)
          document
        end

      assert {:error, %EncodeError{cause: :invalid_utf8, location: []}} =
               Emitter.documents(documents)
    end
  end
end
