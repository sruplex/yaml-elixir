defmodule YAML.FileTest do
  use ExUnit.Case, async: true

  alias YAML.{ArgumentError, EncodeError, ParsingError}

  @moduletag :tmp_dir

  describe "decode_file" do
    test "decodes the file with the given options", %{tmp_dir: dir} do
      path = Path.join(dir, "a.yml")
      File.write!(path, "a: 1\n---\nb: 2\n")

      assert YAML.decode_file(path) == {:ok, [%{"a" => 1}, %{"b" => 2}]}
      assert YAML.decode_file(path, return: :first_document) == {:ok, %{"a" => 1}}
      assert YAML.decode_file!(path, atomize_keys: true) == [%{a: 1}, %{b: 2}]
    end

    test "returns a File.Error for a missing file", %{tmp_dir: dir} do
      path = Path.join(dir, "missing.yml")

      assert YAML.decode_file(path) ==
               {:error, %File.Error{reason: :enoent, action: "read file", path: path}}

      assert_raise File.Error, ~r/could not read file/, fn -> YAML.decode_file!(path) end
      assert {:error, %File.Error{path: ^path}} = YAML.decode_file(String.to_charlist(path))
    end

    test "returns the parsing and option errors of decode", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.yml")
      File.write!(path, "a: [1\n")

      assert {:error, %ParsingError{}} = YAML.decode_file(path)
      assert {:error, %ArgumentError{option: :return}} = YAML.decode_file(path, return: :x)
      assert_raise ParsingError, fn -> YAML.decode_file!(path) end
    end
  end

  describe "encode_file" do
    test "writes the encoded term and decodes back", %{tmp_dir: dir} do
      path = Path.join(dir, "out.yml")
      data = %{"b" => [1, 2], "a" => "x"}

      assert YAML.encode_file(data, path, sort_maps: true) == :ok
      assert File.read!(path) == "---\na: x\nb:\n  - 1\n  - 2\n"
      assert YAML.decode_file(path) == {:ok, data}
      assert YAML.encode_file!([1], path) == :ok
      assert File.read!(path) == "---\n- 1\n"
    end

    test "returns a File.Error when the file can't be written", %{tmp_dir: dir} do
      path = Path.join([dir, "missing_dir", "out.yml"])

      assert YAML.encode_file(1, path) ==
               {:error, %File.Error{reason: :enoent, action: "write to file", path: path}}

      assert_raise File.Error, ~r/could not write to file/, fn -> YAML.encode_file!(1, path) end
      assert {:error, %File.Error{path: ^path}} = YAML.encode_file(1, String.to_charlist(path))
    end

    test "returns encode and option errors without writing", %{tmp_dir: dir} do
      path = Path.join(dir, "out.yml")

      assert {:error, %EncodeError{}} = YAML.encode_file(%{a: self()}, path)

      assert {:error, %ArgumentError{option: :sort_maps}} =
               YAML.encode_file(1, path, sort_maps: 1)

      assert_raise EncodeError, fn -> YAML.encode_file!(self(), path) end
      refute File.exists?(path)
    end
  end
end
