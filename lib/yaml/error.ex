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
