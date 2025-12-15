defmodule YAML.Parser do
  @moduledoc """
  Parses YAML strings into AST or simplified Elixir data structures.
  """

  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}
  @yamerl_opts [:str_node_as_binary, :detailed_constr]

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

  def parse!(string) when is_binary(string) do
    string
    |> :yamerl_constr.string(@yamerl_opts)
    |> do_parse()
  end

  defp do_parse({:yamerl_doc, root}) do
    %Document{root: do_parse(root)}
  end

  defp do_parse({:yamerl_map, _, tag, meta, pairs}) do
    %Mapping{
      pairs: Enum.map(pairs, fn {k, v} -> {do_parse(k), do_parse(v)} end),
      meta: build_meta(tag, meta)
    }
  end

  defp do_parse({:yamerl_seq, _, tag, meta, items, doc_count}) do
    %List{items: Enum.map(items, &do_parse/1), meta: build_meta(tag, meta), length: doc_count}
  end

  defp do_parse({:yamerl_null, _, tag, meta}) do
    %Scalar{value: nil, meta: build_meta(tag, meta)}
  end

  defp do_parse({node_type, _, tag, meta, value})
       when node_type in [
              :yamerl_str,
              :yamerl_int,
              :yamerl_bool,
              :yamerl_float,
              :yamerl_binary,
              :yamerl_ip_addr
            ] do
    %Scalar{value: value, meta: build_meta(tag, meta)}
  end

  defp do_parse(
         {:yamerl_timestamp, _data, tag, meta, year, month, day, hour, minute, second, _fraction,
          _tz}
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    meta = build_meta(tag, meta)
    hour = normalize_integer(hour)
    minute = normalize_integer(minute)
    second = normalize_integer(second)
    datetime = NaiveDateTime.new!(year, month, day, hour, minute, second)

    %Scalar{value: datetime, meta: meta}
  end

  defp do_parse(yamerl_result) when is_list(yamerl_result) do
    Enum.map(yamerl_result, &do_parse/1)
  end

  defp do_parse({_type, _data, _tag, _meta, value}) do
    %Scalar{value: value, meta: nil}
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
    iex>YAML.Parser.simplify(ast)
    [%{"key" => "value"}]

  """

  def simplify(%Document{root: root}) do
    simplify(root)
  end

  def simplify(%Mapping{pairs: pairs}) do
    Map.new(pairs, fn {key, value} ->
      {simplify(key), simplify(value)}
    end)
  end

  def simplify(%List{items: items}) do
    Enum.map(items, &simplify/1)
  end

  def simplify(%Scalar{value: value}) do
    value
  end

  def simplify(ast_documents) when is_list(ast_documents) do
    Enum.map(ast_documents, &simplify/1)
  end

  def simplify(value), do: value

  defp build_meta(tag, meta) do
    %Meta{tag: to_string(tag), line: meta[:line], column: meta[:column]}
  end

  defp normalize_integer(v) when is_integer(v), do: v
  defp normalize_integer(_), do: 0
end
