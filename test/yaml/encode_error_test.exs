defmodule YAML.EncodeErrorTest do
  use ExUnit.Case, async: true

  alias YAML.EncodeError

  test "unsupported/2 and invalid_key/2 build the error" do
    assert %EncodeError{cause: :unsupported_type, term: {1, 2}, location: []} =
             error = EncodeError.unsupported({1, 2}, "tuple")

    assert error.message == "cannot encode tuple"

    assert %EncodeError{
             cause: :invalid_key,
             term: [1],
             message: "cannot encode list as a map key"
           } =
             EncodeError.invalid_key([1], "list")
  end

  test "invalid_utf8/1 builds the error" do
    assert %EncodeError{
             cause: :invalid_utf8,
             term: <<255>>,
             message: "cannot encode invalid UTF-8 string"
           } = EncodeError.invalid_utf8(<<255>>)
  end

  test "prepend_location/2 adds a step to the front of the location" do
    error =
      {1, 2}
      |> EncodeError.unsupported("tuple")
      |> EncodeError.prepend_location("port")
      |> EncodeError.prepend_location(0)
      |> EncodeError.prepend_location("servers")

    assert error.location == ["servers", 0, "port"]
  end

  test "the message includes the location when there is one" do
    error = EncodeError.unsupported({1, 2}, "tuple")
    assert Exception.message(error) == "cannot encode tuple"

    error = EncodeError.prepend_location(error, "port")
    assert Exception.message(error) == ~s{cannot encode tuple (at ["port"])}
  end

  test "raising shows the location" do
    error = {1, 2} |> EncodeError.unsupported("tuple") |> EncodeError.prepend_location(0)

    assert_raise EncodeError, "cannot encode tuple (at [0])", fn -> raise error end
  end
end
