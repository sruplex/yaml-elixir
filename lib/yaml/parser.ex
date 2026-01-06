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

  def parse(string, opts \\ []) when is_binary(string) do
    merge? = Keyword.get(opts, :enable_merge, true)

    {:ok,
     string
     |> :yamerl_constr.string(@yamerl_opts)
     |> do_parse(merge?)}
  catch
    {:yamerl_exception, error} ->
      {:error, YAML.ParsingError.build_error(error)}
  end

  def parse!(string, opts \\ []) when is_binary(string) do
    case parse(string, opts) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  defp do_parse({:yamerl_doc, root}, merge?) do
    %Document{root: do_parse(root, merge?)}
  end

  defp do_parse({:yamerl_map, _, tag, meta, pairs}, merge?) do
    parsed_pairs =
      Enum.map(pairs, fn {k, v} ->
        {do_parse(k, merge?), do_parse(v, merge?)}
      end)

    final_pairs =
      if merge?, do: apply_merge(parsed_pairs), else: parsed_pairs

    %Mapping{
      pairs: final_pairs,
      meta: build_meta(tag, meta)
    }
  end

  defp do_parse({:yamerl_seq, _, tag, meta, items, doc_count}, merge?) do
    %List{
      items: Enum.map(items, &do_parse(&1, merge?)),
      meta: build_meta(tag, meta),
      length: doc_count
    }
  end

  defp do_parse({:yamerl_null, _, tag, meta}, _merge?) do
    %Scalar{value: nil, meta: build_meta(tag, meta)}
  end

  defp do_parse({node_type, _, tag, meta, value}, _merge?)
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
          _tz},
         _merge?
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    meta = build_meta(tag, meta)
    hour = normalize_integer(hour)
    minute = normalize_integer(minute)
    second = normalize_integer(second)

    %Scalar{
      value: NaiveDateTime.new!(year, month, day, hour, minute, second),
      meta: meta
    }
  end

  defp do_parse(yamerl_result, merge?) when is_list(yamerl_result) do
    Enum.map(yamerl_result, &do_parse(&1, merge?))
  end

  defp do_parse({_type, _data, _tag, _meta, value}, _merge?) do
    %Scalar{value: value, meta: nil}
  end

  defp apply_merge(pairs) do
    {merge_pairs, normal_pairs} =
      Enum.split_with(pairs, fn
        {%Scalar{value: "<<"}, _} -> true
        _ -> false
      end)

    merged_pairs =
      Enum.flat_map(merge_pairs, fn {_k, v} ->
        case v do
          %Mapping{pairs: p} ->
            p

          %List{items: items} ->
            Enum.flat_map(items, fn
              %Mapping{pairs: p} -> p
              _ -> []
            end)

          _ ->
            []
        end
      end)

    # YAML rule: local keys override merged ones
    merged_pairs ++ normal_pairs
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
