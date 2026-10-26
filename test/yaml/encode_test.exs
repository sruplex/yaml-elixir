defmodule YAML.EncodeTest do
  use ExUnit.Case, async: true

  alias YAML.{Encode, EncodeError}
  alias YAML.AST.{Document, Scalar}

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
        assert emit_decoded(yaml) == yaml
      end
    end

    test "tags outside the core set are written by their Elixir type" do
      assert emit_decoded("!!binary aGVsbG8=") == "hello"
    end

    test "unsupported scalar values return an error" do
      node = %Scalar{value: {1, 2}, meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str"}}
      assert {:error, %EncodeError{type: :unsupported_type, term: {1, 2}}} = Encode.node(node)
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

      assert {:error, %EncodeError{type: :invalid_utf8, term: <<255, 104>>}} =
               Encode.node(node)
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
end
