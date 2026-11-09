defmodule YAML.Support.Point do
  @moduledoc false
  @derive YAML.Encoder
  defstruct [:x, :y]
end

defmodule YAML.Support.User do
  @moduledoc false
  @derive {YAML.Encoder, only: [:name, :email]}
  defstruct [:name, :email, :password]
end

defmodule YAML.Support.Session do
  @moduledoc false
  @derive {YAML.Encoder, except: [:token]}
  defstruct [:id, :user, :token]
end

defmodule YAML.Support.Money do
  @moduledoc false
  defstruct [:amount, :currency]

  defimpl YAML.Encoder do
    def encode(%{amount: amount, currency: currency}), do: "#{amount} #{currency}"
  end

  defimpl YAML.Decoder do
    def decode(_template, text) when is_binary(text) do
      [amount, currency] = String.split(text, " ")
      %YAML.Support.Money{amount: amount, currency: currency}
    end
  end
end

defmodule YAML.Support.Order do
  @moduledoc false
  @derive YAML.Encoder
  defstruct id: nil, price: %YAML.Support.Money{}
end

defmodule YAML.Support.Box do
  @moduledoc false
  defstruct [:content]

  defimpl YAML.Encoder do
    def encode(%{content: content}), do: content
  end
end

defmodule YAML.Support.Broken do
  @moduledoc false
  defstruct []

  defimpl YAML.Encoder do
    def encode(_value), do: Enum.to_list(%URI{})
  end
end

defmodule YAML.Support.Team do
  @moduledoc false
  @derive YAML.Encoder
  defstruct name: nil, lead: %YAML.Support.User{}, members: [%YAML.Support.User{}]
end
