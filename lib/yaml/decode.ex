defmodule YAML.Decode do
  @moduledoc false

  # Whether a value can be given as the :as option
  @spec template?(term()) :: boolean()
  def template?([template]), do: template?(template)
  def template?(template), do: is_struct(template)

  # Decoded data as the structs of the :as option
  @spec as(term(), term()) :: term()
  def as(list, [template]) when is_list(list), do: Enum.map(list, &as(&1, template))
  # A tag function may already return the template's struct
  def as(%struct{} = value, %struct{}), do: value
  def as(value, %_{} = template), do: YAML.Decoder.decode(template, value)
  def as(data, _template), do: data
end
