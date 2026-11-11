defmodule YAML.Parser do
  @moduledoc """
  Parses YAML strings into AST or simplified Elixir data structures.
  """

  alias YAML.Native
  alias YAML.ParsingError
  alias YAML.AST.{Document, Scalar, List, Mapping}

  # Inputs from this size take over a millisecond, so they run on a dirty scheduler
  @dirty_size 2_000

  @schemas [:failsafe, :json, :core, :yaml11]

  @doc """
  Parses YAML string into AST (Abstract Syntax Tree) with full metadata.
  Returns a list of `YAML.AST.Document` structs since YAML files can contain
  multiple documents.

  ## Examples

    iex> YAML.Parser.parse!("key: value")
    [
      %YAML.AST.Document{
        root: %YAML.AST.Mapping{
          pairs: [
            {%YAML.AST.Scalar{value: "key", meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 1, column: 1}},
             %YAML.AST.Scalar{value: "value", meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 1,column: 6}}}
          ],
          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 1, column: 1}
        }
      }
    ]
  """

  def parse(string, schema \\ :core) when is_binary(string) and schema in @schemas do
    result =
      if byte_size(string) < @dirty_size,
        do: Native.parse(string, schema),
        else: Native.parse_dirty(string, schema)

    case result do
      {:ok, documents} -> {:ok, documents}
      {:error, message, line, column} -> {:error, ParsingError.build(message, line, column)}
    end
  end

  def parse!(string, schema \\ :core) when is_binary(string) and schema in @schemas do
    case parse(string, schema) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  @doc """
  Simplifies AST into plain Elixir data structures (maps, lists).

  ## Examples
    iex> ast = [
         %YAML.AST.Document{
           root: %YAML.AST.Mapping{
             pairs: [
               {%YAML.AST.Scalar{value: "key", meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 1, column: 1}},
                %YAML.AST.Scalar{value: "value", meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 1,column: 6}}}
             ],
             meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 1, column: 1}
           }
         }
       ]
    iex>YAML.Parser.simplify(ast, atomize_keys)
    [%{"key" => "value"}]

  """
  def simplify(ast, atomize_keys \\ false)

  def simplify(%Document{root: root}, atomize_keys) do
    simplify(root, atomize_keys)
  end

  def simplify(%Mapping{pairs: pairs}, atomize_keys) do
    Map.new(pairs, fn {key, value} ->
      {key |> simplify(atomize_keys) |> atomize_key(atomize_keys), simplify(value, atomize_keys)}
    end)
  end

  def simplify(%List{items: items}, atomize_keys) do
    Enum.map(items, &simplify(&1, atomize_keys))
  end

  def simplify(%Scalar{value: value}, _atomize_keys) do
    value
  end

  def simplify(ast_documents, atomize_keys) when is_list(ast_documents) do
    Enum.map(ast_documents, &simplify(&1, atomize_keys))
  end

  def simplify(value, _atomize_keys), do: value

  defp atomize_key(key, false) when is_binary(key), do: key
  defp atomize_key(key, nil) when is_binary(key), do: key

  defp atomize_key(key, :safe) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end

  defp atomize_key(key, true) when is_binary(key), do: String.to_atom(key)
  defp atomize_key(key, _), do: key
end
