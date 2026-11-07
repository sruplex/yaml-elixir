defmodule YAML.LoadTest do
  # Not async: stops and unloads yamerl for the whole VM
  use ExUnit.Case, async: false

  test "decode works when yamerl is not loaded" do
    :ok = Application.stop(:yamerl)
    :ok = Application.unload(:yamerl)
    on_exit(fn -> Application.ensure_all_started(:yamerl) end)

    assert YAML.decode("a: 1") == {:ok, %{"a" => 1}}
  end
end
