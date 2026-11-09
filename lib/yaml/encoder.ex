defprotocol YAML.Encoder do
  @moduledoc """
  Protocol for encoding structs, returning the plain data to write in their place.

  Derive it to write a struct's fields as a map, optionally with `:only` or `:except`:

      defmodule User do
        @derive {YAML.Encoder, only: [:name, :email]}
        defstruct [:name, :email, :password]
      end

  Or implement it to write any other data:

      defimpl YAML.Encoder, for: Money do
        def encode(%Money{amount: amount, currency: currency}), do: "\#{amount} \#{currency}"
      end

  The returned data may hold other structs, which are encoded the same way.
  """

  @doc "Returns the plain data (maps, lists and scalars) to write in place of `value`."
  @spec encode(t()) :: term()
  def encode(value)
end

defimpl YAML.Encoder, for: Any do
  defmacro __deriving__(module, struct, opts) do
    only = Keyword.get(opts, :only, Map.keys(struct) -- [:__struct__])
    fields = only -- Keyword.get(opts, :except, [])

    quote do
      defimpl YAML.Encoder, for: unquote(module) do
        def encode(struct), do: Map.take(struct, unquote(fields))
      end
    end
  end

  def encode(value), do: raise(Protocol.UndefinedError, protocol: @protocol, value: value)
end

defimpl YAML.Encoder, for: [Date, Time, NaiveDateTime, DateTime] do
  def encode(value), do: @for.to_iso8601(value)
end
