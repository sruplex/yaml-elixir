defmodule YAML.Parser do
  @yamerl_opts [:str_node_as_binary, :detailed_constr]

  def parse!(string) when is_binary(string) do
    string
    |> :yamerl_constr.string(@yamerl_opts)
    |> Enum.map(&normalize/1)
  end

  defp normalize({:yamerl_seq, _, _, _, list, _count}) do
    Enum.map(list, &normalize/1)
  end

  defp normalize({:yamerl_map, _, _, _, list}) do
    Map.new(list, fn {key, value} ->
      {normalize(key), normalize(value)}
    end)
  end

  defp normalize([]), do: nil
  defp normalize({:yamerl_null, _, _, _}), do: nil
  defp normalize({:yamerl_doc, document}), do: normalize(document)
  defp normalize({:yamerl_str, _, _, _, value}), do: value
  defp normalize({:yamerl_int, _, _, _, value}), do: value
  defp normalize({_type, _data, _tag, _meta, value}), do: value
end
