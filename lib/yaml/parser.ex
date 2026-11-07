defmodule YAML.Parser do
  @moduledoc """
  Parses YAML strings into AST or simplified Elixir data structures.
  """

  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}

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

  def parse(string, yamerl_opts) when is_binary(string) do
    # The user's node_mods go first, so they're tried before ours
    {node_mods, yamerl_opts} = Keyword.pop(yamerl_opts, :node_mods, [])
    node_mods = {:node_mods, node_mods ++ [YAML.MergeKey]}
    opts = [:str_node_as_binary, :detailed_constr, node_mods | yamerl_opts]

    # yamerl reads its app env on every parse, so it must be loaded
    if Application.get_env(:yamerl, :node_mods) == nil, do: Application.load(:yamerl)

    try do
      :yamerl_constr.string(string, opts)
    rescue
      # yamerl's parser crashes on some input instead of returning its own error
      _error ->
        {:error,
         %YAML.ParsingError{type: :parse_error, message: "yamerl failed to parse the input"}}
    catch
      {:yamerl_exception, error} ->
        {:error, YAML.ParsingError.build_error(error)}
    else
      documents -> {:ok, do_parse(documents)}
    end
  end

  def parse!(string, yamerl_opts) when is_binary(string) do
    case parse(string, yamerl_opts) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  defp do_parse({:yamerl_doc, root}), do: %Document{root: do_value(root)}

  defp do_parse({:yamerl_map, _, tag, meta, pairs}) do
    %Mapping{
      pairs: Enum.map(pairs, fn {k, v} -> {do_parse(k), do_value(v)} end),
      meta: build_meta(tag, meta)
    }
  end

  defp do_parse({:yamerl_seq, _, tag, meta, items, doc_count}) do
    %List{items: Enum.map(items, &do_value/1), meta: build_meta(tag, meta), length: doc_count}
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

  # YAML.MergeKey tags every plain "<<"; anywhere but a key it's a string
  defp do_value({:yamerl_str, mod, ~c"tag:yaml.org,2002:merge", pres, value}),
    do: do_parse({:yamerl_str, mod, ~c"tag:yaml.org,2002:str", pres, value})

  defp do_value(node), do: do_parse(node)

  defp build_meta(tag, meta) do
    %Meta{tag: to_string(tag), line: meta[:line], column: meta[:column]}
  end

  defp normalize_integer(v) when is_integer(v), do: v
  defp normalize_integer(_), do: 0

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
