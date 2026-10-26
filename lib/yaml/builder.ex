defmodule YAML.Builder do
  @moduledoc false

  alias YAML.AST.{Document, Scalar, List, Mapping, Meta}
  alias YAML.EncodeError

  @null_meta %Meta{tag: "tag:yaml.org,2002:null"}
  @bool_meta %Meta{tag: "tag:yaml.org,2002:bool"}
  @int_meta %Meta{tag: "tag:yaml.org,2002:int"}
  @float_meta %Meta{tag: "tag:yaml.org,2002:float"}
  @str_meta %Meta{tag: "tag:yaml.org,2002:str"}
  @seq_meta %Meta{tag: "tag:yaml.org,2002:seq"}
  @map_meta %Meta{tag: "tag:yaml.org,2002:map"}

  @spec build(term()) :: {:ok, %Document{}} | {:error, EncodeError.t()}
  def build(term) do
    {:ok, %Document{root: build_node(term)}}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  defp build_node(nil), do: %Scalar{value: nil, meta: @null_meta}
  defp build_node(bool) when is_boolean(bool), do: %Scalar{value: bool, meta: @bool_meta}
  defp build_node(int) when is_integer(int), do: %Scalar{value: int, meta: @int_meta}
  defp build_node(float) when is_float(float), do: %Scalar{value: float, meta: @float_meta}

  # Decode returns .inf, -.inf and .nan as these atoms
  defp build_node(special) when special in [:"+inf", :"-inf", :nan],
    do: %Scalar{value: special, meta: @float_meta}

  defp build_node(binary) when is_binary(binary), do: %Scalar{value: binary, meta: @str_meta}

  defp build_node(atom) when is_atom(atom),
    do: %Scalar{value: Atom.to_string(atom), meta: @str_meta}

  defp build_node(%Date{} = date), do: %Scalar{value: Date.to_iso8601(date), meta: @str_meta}
  defp build_node(%Time{} = time), do: %Scalar{value: Time.to_iso8601(time), meta: @str_meta}

  defp build_node(%NaiveDateTime{} = datetime),
    do: %Scalar{value: NaiveDateTime.to_iso8601(datetime), meta: @str_meta}

  defp build_node(%DateTime{} = datetime),
    do: %Scalar{value: DateTime.to_iso8601(datetime), meta: @str_meta}

  defp build_node(list) when is_list(list) do
    items = build_items(list, 0)
    %List{items: items, meta: @seq_meta, length: length(items)}
  end

  defp build_node(map) when is_map(map) and not is_struct(map) do
    %Mapping{
      pairs: Enum.map(map, fn {key, value} -> {build_key(key), build_child(value, key)} end),
      meta: @map_meta
    }
  end

  defp build_node(term),
    do: throw({:encode_error, EncodeError.unsupported(term, type_name(term))})

  defp build_items([head | tail], index),
    do: [build_child(head, index) | build_items(tail, index + 1)]

  defp build_items([], _index), do: []

  defp build_items(tail, _index),
    do: throw({:encode_error, EncodeError.unsupported(tail, "improper list")})

  # Adds the map key or list index to the location of an error from inside the value
  defp build_child(value, step) do
    build_node(value)
  catch
    {:encode_error, error} -> throw({:encode_error, EncodeError.prepend_location(error, step)})
  end

  defp build_key(key) when is_binary(key) or is_atom(key) or is_number(key), do: build_node(key)
  defp build_key(key), do: throw({:encode_error, EncodeError.invalid_key(key, type_name(key))})

  defp type_name(%module{}), do: "#{inspect(module)} struct"
  defp type_name(term) when is_tuple(term), do: "tuple"
  defp type_name(term) when is_pid(term), do: "pid"
  defp type_name(term) when is_reference(term), do: "reference"
  defp type_name(term) when is_function(term), do: "function"
  defp type_name(term) when is_port(term), do: "port"
  defp type_name(term) when is_bitstring(term), do: "bitstring"
  defp type_name(term) when is_list(term), do: "list"
  defp type_name(term) when is_map(term), do: "map"
  defp type_name(_term), do: "term"
end
