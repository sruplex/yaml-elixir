defmodule YAML.ParsingError do
  defexception [:message, :location, :type]

  # Exception Callbacks
  # -------------------

  def message(error) do
    "#{error.message} (at #{inspect(error.location)})"
  end

  # Helper API
  # ----------

  def build_tuple(error) do
    {:error, {:invalid_yaml, format(error)}}
  end

  def build_error(error) do
    struct(YAML.ParsingError, format(error))
  end

  # Private Methods
  # ---------------

  defp format([error | _rest]), do: format(error)

  defp format({type, _level, message, loc1, loc2, _code, _token, _other}) do
    [type: normalize(type), message: to_string(message), location: {loc1, loc2}]
  end

  defp normalize(:yamerl_parsing_error), do: :parse_error
  defp normalize(type), do: type
end

defmodule YAML.ArgumentError do
  defexception [:message, :option, :value]

  @type t :: %__MODULE__{
          message: String.t(),
          option: atom() | nil,
          value: term()
        }

  def invalid_option(option, value, reason \\ nil) do
    %__MODULE__{
      option: option,
      value: value,
      message: reason || "invalid value for option #{inspect(option)}"
    }
  end
end

defmodule YAML.EncodeError do
  @moduledoc """
  Returned when a value can't be encoded; `:cause` says why and `:location` is the path to it.
  """

  defexception [:message, :term, :cause, location: []]

  @type t :: %__MODULE__{
          message: String.t(),
          term: term(),
          cause: :unsupported_type | :invalid_key | :invalid_utf8,
          location: [term()]
        }

  # Exception Callbacks
  # -------------------

  def message(%__MODULE__{message: message, location: []}), do: message

  def message(%__MODULE__{message: message, location: location}),
    do: "#{message} (at #{inspect(location)})"

  # Helper API
  # ----------

  @doc false
  def unsupported(term, type) do
    %__MODULE__{
      term: term,
      cause: :unsupported_type,
      message: "cannot encode #{type}"
    }
  end

  @doc false
  def invalid_key(key, type) do
    %__MODULE__{
      term: key,
      cause: :invalid_key,
      message: "cannot encode #{type} as a map key"
    }
  end

  @doc false
  def invalid_utf8(string) do
    %__MODULE__{
      term: string,
      cause: :invalid_utf8,
      message: "cannot encode invalid UTF-8 string"
    }
  end

  @doc false
  def prepend_location(%__MODULE__{location: location} = error, step),
    do: %{error | location: [step | location]}
end
