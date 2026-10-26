defmodule YAML.EmitterTest do
  use ExUnit.Case, async: true

  alias YAML.{Builder, Emitter, EncodeError}
  alias YAML.AST.{Document, Scalar}

  defp emit(term) do
    assert {:ok, %Document{root: root}} = Builder.build(term)
    emit_node(root)
  end

  defp emit_node(node) do
    assert {:ok, iodata} = Emitter.emit(node)
    IO.iodata_to_binary(iodata)
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
      assert {:error, %EncodeError{cause: :unsupported_type, term: {1, 2}}} = Emitter.emit(node)
    end

    test "scalars without meta are written by their Elixir type" do
      assert {:ok, "1"} = Emitter.emit(%Scalar{value: 1, meta: nil})
      assert {:ok, ".inf"} = Emitter.emit(%Scalar{value: :"+inf", meta: nil})
    end
  end

  describe "strings" do
    test "safe strings are written plain" do
      for string <- ["hello", "hello world", "a:b", "a#b", "tRuE", "quote\"in", "日本語"] do
        assert emit(string) == string
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
               Emitter.emit(node)
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
end
