defmodule YAML.ParsingError do
  defexception [:message, :location, :type]

  @type t :: %__MODULE__{
          message: String.t(),
          location: {pos_integer(), pos_integer()},
          type: atom()
        }

  # Exception Callbacks
  # -------------------

  def message(error) do
    "#{error.message} (at #{inspect(error.location)})"
  end

  # Helper API
  # ----------

  @doc false
  def build(message, line, column) do
    %__MODULE__{type: :parse_error, message: message, location: {line, column}}
  end
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
  Error returned or raised when a value can't be encoded.
  """

  defexception [:message, :term, :type, location: []]

  @type t :: %__MODULE__{
          message: String.t(),
          term: term(),
          type: :unsupported_type | :invalid_key | :duplicate_key | :invalid_utf8,
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
  def unsupported(term, name) do
    %__MODULE__{
      term: term,
      type: :unsupported_type,
      message: "cannot encode #{name}"
    }
  end

  @doc false
  def invalid_key(key, name) do
    %__MODULE__{
      term: key,
      type: :invalid_key,
      message: "cannot encode #{name} as a map key"
    }
  end

  @doc false
  def duplicate_key(key) do
    %__MODULE__{
      term: key,
      type: :duplicate_key,
      message: "duplicate map key #{inspect(to_string(key))}"
    }
  end

  @doc false
  def invalid_utf8(string) do
    %__MODULE__{
      term: string,
      type: :invalid_utf8,
      message: "cannot encode invalid UTF-8 string"
    }
  end

  @doc false
  def prepend_location(%__MODULE__{location: location} = error, step),
    do: %{error | location: [step | location]}
end
