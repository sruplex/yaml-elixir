defmodule YAML.StreamChunksTest do
  use ExUnit.Case, async: true

  alias YAML.ParsingError

  defmodule User do
    defstruct [:name, :n]
  end

  @list Enum.map_join(
          1..12_000,
          &"- id: #{&1}\n  name: user #{&1}\n  tags: [a, b]\n  note: |\n    x\n"
        )
  @map Enum.map_join(1..12_000, &"key#{&1}:\n  id: #{&1}\n  list: [x, y]\n")

  describe "decode_stream/2 with a document over 256 KB" do
    test "gives a long list in pieces, each a list of its items" do
      pieces = stream([@list])

      assert length(pieces) > 1
      assert Enum.all?(pieces, &match?([_ | _], &1))
      assert Enum.concat(pieces) == YAML.decode!(@list)
    end

    test "gives a long map in pieces, each a map of its pairs" do
      pieces = stream([@map])

      assert length(pieces) > 1
      assert Enum.all?(pieces, &is_map/1)
      assert Enum.reduce(pieces, &Map.merge(&2, &1)) == YAML.decode!(@map)
    end

    test "gives the documents around it whole" do
      pieces = stream(["a: 1\n---\n" <> @list <> "---\nb: 2\n"])

      assert hd(pieces) == %{"a" => 1}
      assert List.last(pieces) == %{"b" => 2}
      assert pieces |> Enum.slice(1..-2//1) |> Enum.concat() == YAML.decode!(@list)
    end

    test "gives the data of decode/2 for every shape, cut at every point" do
      tags = %{"!m" => &{:m, &1}, "tag:e,1:x" => &{:x, &1}, "!list" => &length/1}

      inputs = [
        {"- !m 5\n- !m 6\n", tags: tags},
        {"%TAG !e! tag:e,1:\n---\n- !e!x 1\n- !e!x 2\n", tags: tags},
        {"--- !list\n- 1\n- 2\n", tags: tags},
        {"--- !!set\n? a\n? b\n", []},
        {"a: |\n  x\n\n  y\nb: >-\n  z\n", []},
        {"a: 1\n# c\n\nb: 2\n", []},
        {"? a\n: 1\n\"b c\": 2\n'd': 3\n-k: 4\n", []},
        {"a:\n- 1\n- 2\nb: 3\n", []},
        {"  - 1\n  - 2\n", []},
        {"a: 1\r\nb: 2\r\n", []},
        {"\uFEFFa: 1\nb: 2\n", []},
        {"a: 1\nb: {c: 2}\n", atomize_keys: true},
        {"a: yes\nb: 1\n", schema: :yaml11},
        {"hello\n", []},
        {"records: [1,\n  2]\nz: 3\n", []},
        {"", []}
      ]

      for {yaml, opts} <- inputs, size <- [1, 10, 65_536] do
        opts = Keyword.merge([return: :all_documents], opts)

        pieces =
          for {:ok, piece} <-
                [yaml] |> YAML.Chunks.stream(&YAML.decode(&1, opts), chunk_size: size),
              do: piece

        assert joined(pieces) == YAML.decode!(yaml, opts), inspect({yaml, size})
      end
    end

    test "cuts a long value under one key into maps of that key and some of its items" do
      for records <- [indent(@list), @list] do
        yaml = "version: 1\nrecords:\n" <> records <> "end: 2\n"
        pieces = stream([yaml])
        whole = YAML.decode!(yaml)

        assert hd(pieces) == %{"version" => 1}
        assert List.last(pieces) == %{"end" => 2}
        middle = Enum.slice(pieces, 1..-2//1)
        assert length(middle) > 1
        assert Enum.all?(middle, &match?(%{"records" => [_ | _]}, &1))
        assert Enum.flat_map(middle, & &1["records"]) == whole["records"]
      end
    end

    test "cuts a long map under one key into maps of that key and some of its pairs" do
      yaml = "users:\n" <> indent(Enum.map_join(1..40_000, &"key#{&1}:\n  id: #{&1}\n"))
      pieces = stream([yaml])

      assert length(pieces) > 1

      assert pieces |> Enum.map(& &1["users"]) |> Enum.reduce(&Map.merge(&2, &1)) ==
               YAML.decode!(yaml)["users"]
    end

    test "keeps a long value under one key whole when it can't be cut" do
      text = "notes: |\n" <> String.duplicate("  line of text\n", 80_000)
      flow = "records: [\n" <> String.duplicate("  1,\n", 160_000) <> "]\n"

      for yaml <- [text, flow] do
        assert stream([yaml]) == [YAML.decode!(yaml)]
      end
    end

    test "gives a long value under one key with its lines in the stream" do
      yaml = "version: 1\nrecords:\n" <> indent(@list) <> "  - [broken\n"
      {:error, %ParsingError{location: location}} = YAML.decode(yaml)

      assert [{:error, %ParsingError{location: ^location}}] =
               [yaml] |> YAML.decode_stream() |> Enum.filter(&match?({:error, _}, &1))
    end

    test "gives a root that can't be cut in one piece" do
      for root <- ["--- |\n", "--- >\n"] do
        yaml = root <> String.duplicate("  text line\n", 40_000)
        assert stream([yaml]) == [YAML.decode!(yaml)]
      end
    end

    test "gives the same pieces however the input is read" do
      expected = stream([@list])

      for size <- [7, 4_096, 65_536, 1_000_000] do
        assert @list |> chunked(size) |> stream() == expected
      end
    end

    test "keeps a multi-byte character cut between two reads" do
      yaml = String.duplicate("- é ü 日本\n", 80_000)
      assert yaml |> chunked(3) |> stream() |> Enum.concat() |> Enum.uniq() == ["é ü 日本"]
    end

    test "gives an item longer than a piece whole" do
      big = String.duplicate("x", 600_000)
      assert stream(["- #{big}\n- b\n"]) |> Enum.concat() == [big, "b"]
    end

    test "applies the decode options to each piece" do
      yaml = String.replace(@list, "tags: [a, b]", "tags: !set [a, b]")
      tags = %{"!set" => &MapSet.new/1}

      for users <- stream([yaml], tags: tags, atomize_keys: true), user <- users do
        assert %{id: _, tags: %MapSet{}} = user
      end

      users = Enum.map_join(1..5_000, &"- name: n#{&1}\n  n: #{&1}\n")
      assert [[%User{name: "n1", n: 1} | _] | _] = stream([users], as: [%User{}])
    end

    test "gives AST pieces with their lines in the whole stream, with detailed: true" do
      yaml = "a: 1\n---\n" <> @list
      [_first, whole] = YAML.decode!(yaml, detailed: true, return: :all_documents)
      [first | pieces] = stream([yaml], detailed: true)

      assert first.root.pairs |> hd() |> elem(0) |> Map.get(:meta) |> Map.get(:line) == 1
      assert length(pieces) > 1
      assert Enum.flat_map(pieces, & &1.root.items) == whole.root.items
    end

    test "decodes each piece of a long map into the :as struct" do
      map = Enum.map_join(1..40_000, &"k#{&1}: #{&1}\n") <> "name: a\nn: 1\n"
      structs = stream([map], as: %User{})

      assert length(structs) > 1
      assert Enum.all?(structs, &is_struct(&1, User))
      assert List.last(structs) == %User{name: "a", n: 1}
    end

    test "finds an anchor in the same piece, and gives an error for one further back" do
      near = "- &b {x: 1}\n- <<: *b\n  y: 2\n" <> @list

      assert stream([near]) |> Enum.concat() |> Enum.take(2) == [
               %{"x" => 1},
               %{"x" => 1, "y" => 2}
             ]

      far = "- &b {x: 1}\n" <> @list <> @list <> "- *b\n"

      assert [{:error, %ParsingError{message: message}}] =
               [far] |> YAML.decode_stream() |> Enum.filter(&match?({:error, _}, &1))

      assert message =~ "unknown anchor"
    end

    test "gives an error with its line in the stream, skips the rest of that document, then goes on" do
      broken = @list <> "- [broken\n" <> @list
      {:error, %ParsingError{location: {line, column}}} = YAML.decode(broken)

      results =
        ["a: 1\n---\n" <> broken <> "---\nb: 2\n"] |> YAML.decode_stream() |> Enum.to_list()

      assert [{:error, %ParsingError{location: {at, ^column}}}] =
               Enum.filter(results, &match?({:error, _}, &1))

      assert at == line + 2
      assert hd(results) == {:ok, %{"a" => 1}}
      assert List.last(results) == {:ok, %{"b" => 2}}
    end

    test "gives each small document and an error among them with its line" do
      yaml = Enum.map_join(1..1_000, &"---\nid: #{&1}\n") <> "---\nid: [\n---\nid: 0\n"
      results = [yaml] |> YAML.decode_stream() |> Enum.to_list()

      assert Enum.take(results, 1_000) == Enum.map(1..1_000, &{:ok, %{"id" => &1}})

      assert [{:error, %ParsingError{location: {2002, 6}}}, {:ok, %{"id" => 0}}] =
               Enum.drop(results, 1_000)
    end

    test "raises an error from a :tags function in the caller" do
      tags = %{"!bad" => fn _ -> raise ArgumentError, "bad value" end}
      yaml = @list <> "- !bad x\n"

      assert_raise ArgumentError, "bad value", fn -> stream([yaml], tags: tags) end
    end

    test "is lazy" do
      assert [[_ | _], [_ | _]] = Stream.cycle(["- a\n"]) |> YAML.decode_stream!() |> Enum.take(2)
    end
  end

  defp stream(reads, opts \\ []), do: reads |> YAML.decode_stream!(opts) |> Enum.to_list()

  defp indent(yaml), do: yaml |> String.split("\n", trim: true) |> Enum.map_join(&"  #{&1}\n")

  defp joined([]), do: []
  defp joined([one]), do: [one]
  defp joined([list | _] = pieces) when is_list(list), do: [Enum.concat(pieces)]
  defp joined(pieces), do: [Enum.reduce(pieces, &Map.merge(&2, &1))]

  defp chunked(string, size) do
    whole = div(byte_size(string), size) * size
    reads = for at <- 0..(whole - 1)//size, do: binary_part(string, at, size)
    reads ++ [binary_part(string, whole, byte_size(string) - whole)]
  end
end
