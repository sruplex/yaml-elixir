defmodule YAML.Parser do
  @moduledoc """
  Parses YAML strings into AST or simplified Elixir data structures.
  """

  alias YAML.AST.{Document, List, Mapping, Meta, Scalar}
  alias YAML.Native
  alias YAML.ParsingError

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
    run(string, schema, :ast)
  end

  @doc false
  def decode(string, schema, enable_merge) do
    run(string, schema, {:plain, enable_merge})
  end

  defp run(string, schema, mode), do: string |> Native.parse(schema, mode) |> finish()

  defp finish({:cont, job}), do: job |> Native.resume() |> finish()

  defp finish({:ok, binary}), do: binary |> :erlang.binary_to_term() |> result()
  defp finish(error), do: result(error)

  defp result({documents, []}), do: {:ok, documents}
  defp result({documents, aliased}), do: {:ok, unalias(documents, unalias_table(aliased))}

  defp result({:error, message, line, column}),
    do: {:error, ParsingError.build(message, line, column)}

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
    iex> YAML.Parser.simplify(ast)
    [%{"key" => "value"}]

  """
  def simplify(ast, atomize_keys \\ false, tags \\ %{})

  def simplify(%Document{root: root}, atomize_keys, tags) do
    simplify(root, atomize_keys, tags)
  end

  def simplify(%Mapping{pairs: pairs, meta: meta}, atomize_keys, tags) do
    pairs
    |> Map.new(fn {key, value} ->
      {key |> simplify(atomize_keys, tags) |> atomize_key(atomize_keys),
       simplify(value, atomize_keys, tags)}
    end)
    |> handle_tag(meta, tags)
  end

  def simplify(%List{items: items, meta: meta}, atomize_keys, tags) do
    items
    |> Enum.map(&simplify(&1, atomize_keys, tags))
    |> handle_tag(meta, tags)
  end

  def simplify(%Scalar{value: value, meta: meta}, _atomize_keys, tags) do
    handle_tag(value, meta, tags)
  end

  def simplify(ast_documents, atomize_keys, tags) when is_list(ast_documents) do
    Enum.map(ast_documents, &simplify(&1, atomize_keys, tags))
  end

  def simplify(value, _atomize_keys, _tags), do: value

  defp handle_tag(value, _meta, tags) when map_size(tags) == 0, do: value

  defp handle_tag(value, %Meta{tag: tag}, tags) do
    case tags do
      %{^tag => fun} -> fun.(value)
      _ -> value
    end
  end

  defp unalias_table(aliased) do
    aliased
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, index}, table ->
      Map.put(table, index, unalias(value, table))
    end)
  end

  defp unalias({:__yaml_alias__, index}, table), do: Map.fetch!(table, index)
  defp unalias({key, value}, table), do: {unalias(key, table), unalias(value, table)}
  defp unalias(list, table) when is_list(list), do: Enum.map(list, &unalias(&1, table))

  defp unalias(map, table) when is_map(map),
    do:
      map
      |> Map.to_list()
      |> Map.new(fn {key, value} -> {unalias(key, table), unalias(value, table)} end)

  defp unalias(value, _table), do: value

  @doc false
  def atomize_keys(data, mode) when mode in [false, nil], do: data

  def atomize_keys(map, mode) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {key |> atomize_keys(mode) |> atomize_key(mode), atomize_keys(value, mode)}
    end)
  end

  def atomize_keys(list, mode) when is_list(list), do: Enum.map(list, &atomize_keys(&1, mode))
  def atomize_keys(value, _mode), do: value

  defp atomize_key(key, false) when is_binary(key), do: key
  defp atomize_key(key, nil) when is_binary(key), do: key

  defp atomize_key(key, :safe) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp atomize_key(key, true) when is_binary(key), do: String.to_atom(key)
  defp atomize_key(key, _), do: key
end
