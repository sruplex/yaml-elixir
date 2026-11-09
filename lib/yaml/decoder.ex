defprotocol YAML.Decoder do
  @moduledoc """
  Protocol for decoding into structs, used for each struct given in the `:as` option.

  By default, a map's keys fill the struct's fields:

      YAML.decode("name: Ada", as: %User{})
      #=> {:ok, %User{name: "Ada"}}

  Implement it to decode any other data into the struct:

      defimpl YAML.Decoder, for: Money do
        def decode(_template, text), do: Money.parse!(text)
      end

      YAML.decode("price: 12.50 USD", as: %Order{price: %Money{}})
      #=> {:ok, %Order{price: %Money{amount: Decimal.new("12.50"), currency: :USD}}}
  """

  @fallback_to_any true

  @doc "Returns `value`, decoded from YAML, as the struct of `template`."
  @spec decode(t(), term()) :: term()
  def decode(template, value)
end

defimpl YAML.Decoder, for: Any do
  # A field's default value is the template for its value
  def decode(%_{} = template, map) when is_map(map) and not is_struct(map) do
    template
    |> Map.from_struct()
    |> Enum.reduce(template, fn {field, default}, struct ->
      case fetch(map, field) do
        {:ok, value} -> %{struct | field => YAML.Decode.as(value, default)}
        :error -> struct
      end
    end)
  end

  def decode(_template, value), do: value

  # Keys are strings, or atoms with the atomize_keys option
  defp fetch(map, field) do
    with :error <- Map.fetch(map, Atom.to_string(field)), do: Map.fetch(map, field)
  end
end
