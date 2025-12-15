defmodule YAML.AST do
  @moduledoc """
  YAML AST definitions when parsing or creating YAML objects.

  You would rarely use these yourself, and instead rely on the
  `detailed: true` option passed to `YAML.decode/2` to return
  the YAML documents as an Elixir AST.

  See the (YAML.decode/) and the `:detailed` option for more details.
  """
  defmodule Document do
    @moduledoc false
    defstruct [:root]
  end

  defmodule Meta do
    @moduledoc false
    defstruct [:tag, :line, :column]
  end

  defmodule Scalar do
    @moduledoc false
    defstruct [:value, :meta]
  end

  defmodule List do
    @moduledoc false
    defstruct [:items, :meta, :length]
  end

  defmodule Mapping do
    @moduledoc false
    defstruct [:pairs, :meta]
  end
end
