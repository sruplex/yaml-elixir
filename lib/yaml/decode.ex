defmodule YAML.Decode do
  @moduledoc false

  @spec template?(term()) :: boolean()
  def template?([template]), do: template?(template)
  def template?(template), do: is_struct(template)

  @spec as(term(), term()) :: term()
  def as(list, [template]) when is_list(list), do: Enum.map(list, &as(&1, template))
  def as(%struct{} = value, %struct{}), do: value
  def as(value, %_{} = template), do: YAML.Decoder.decode(template, value)
  def as(data, _template), do: data
end
