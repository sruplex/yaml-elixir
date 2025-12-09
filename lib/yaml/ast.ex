defmodule YAML.AST do
  defmodule Document do
    defstruct [:root]
  end

  defmodule Meta do
    defstruct [:tag, :line, :column]
  end

  defmodule Scalar do
    defstruct [:value, :meta]
  end

  defmodule List do
    defstruct [:items, :meta]
  end

  defmodule Mapping do
    defstruct [:pairs, :meta]
  end
end
