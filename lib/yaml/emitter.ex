defmodule YAML.Emitter do
  @moduledoc false

  alias YAML.AST.Scalar
  alias YAML.EncodeError

  # Plain strings YAML would read as another type, or as a merge or value key
  @reserved ~w(
    true True TRUE false False FALSE null Null NULL ~
    yes Yes YES no No NO on On ON off Off OFF y Y n N << =
  )

  # Characters that must be escaped in a double-quoted string
  defguardp is_escaped_byte(c) when c < 0x20 or c == 0x7F

  defguardp is_escaped_char(c)
            when c in 0x80..0x9F or c in [0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF]

  @spec emit(%Scalar{}) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def emit(node) do
    {:ok, emit_node(node)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  # Walkers
  # -------

  defp emit_node(%Scalar{value: value}), do: write_scalar(value)

  # Writers
  # -------

  # Decode returns .inf, -.inf and .nan as these atoms
  defp write_scalar(:"+inf"), do: ".inf"
  defp write_scalar(:"-inf"), do: "-.inf"
  defp write_scalar(:nan), do: ".nan"

  defp write_scalar(nil), do: "null"
  defp write_scalar(bool) when is_boolean(bool), do: Atom.to_string(bool)
  defp write_scalar(int) when is_integer(int), do: Integer.to_string(int)
  defp write_scalar(float) when is_float(float), do: write_float(float)
  defp write_scalar(str) when is_binary(str), do: write_string(str)

  defp write_scalar(value),
    do: throw({:encode_error, EncodeError.unsupported(value, "scalar")})

  # YAML 1.1 needs a sign in the exponent: 1.0e+20
  defp write_float(float) do
    string = Float.to_string(float)

    case :binary.split(string, "e") do
      [mantissa, "-" <> _ = exponent] -> [mantissa, ?e, exponent]
      [mantissa, exponent] -> [mantissa, "e+", exponent]
      [_] -> string
    end
  end

  # Strings
  # -------

  defp write_string(""), do: ~s("")

  defp write_string(str) do
    if reserved?(str) or quote_start?(str) or not plain_chars?(str),
      do: quoted(str),
      else: str
  end

  for word <- @reserved do
    defp reserved?(unquote(word)), do: true
  end

  defp reserved?(_str), do: false

  defp quote_start?(<<c, _::binary>>) when c in ?0..?9, do: true
  defp quote_start?(<<c, _::binary>>) when c in ~c"+-.?:,[]{}#&*!|>'\"%@`_ ", do: true
  defp quote_start?(_str), do: false

  # Stops at the first reason to quote; invalid UTF-8 also returns false
  defp plain_chars?(<<": ", _::binary>>), do: false
  defp plain_chars?(<<" #", _::binary>>), do: false
  defp plain_chars?(<<":">>), do: false
  defp plain_chars?(<<" ">>), do: false
  defp plain_chars?(<<c, _::binary>>) when is_escaped_byte(c), do: false
  defp plain_chars?(<<c, rest::binary>>) when c < 0x80, do: plain_chars?(rest)
  defp plain_chars?(<<c::utf8, _::binary>>) when is_escaped_char(c), do: false
  defp plain_chars?(<<_::utf8, rest::binary>>), do: plain_chars?(rest)
  defp plain_chars?(<<>>), do: true
  defp plain_chars?(_invalid), do: false

  defp quoted(str), do: [?", escape(str, str, 0, 0), ?"]

  # Copies runs of safe bytes as slices of the original string
  defp escape(<<c, rest::binary>>, str, skip, len) when c in [?", ?\\] or is_escaped_byte(c),
    do: [binary_part(str, skip, len), escape_char(c) | escape(rest, str, skip + len + 1, 0)]

  defp escape(<<c, rest::binary>>, str, skip, len) when c < 0x80,
    do: escape(rest, str, skip, len + 1)

  defp escape(<<c::utf8, rest::binary>>, str, skip, len) when is_escaped_char(c) do
    size = utf8_size(c)
    [binary_part(str, skip, len), escape_char(c) | escape(rest, str, skip + len + size, 0)]
  end

  defp escape(<<c::utf8, rest::binary>>, str, skip, len),
    do: escape(rest, str, skip, len + utf8_size(c))

  defp escape(<<>>, str, skip, len), do: binary_part(str, skip, len)

  defp escape(_invalid, str, _skip, _len),
    do: throw({:encode_error, EncodeError.invalid_utf8(str)})

  defp escape_char(?"), do: ~S(\")
  defp escape_char(?\\), do: ~S(\\)
  defp escape_char(?\n), do: ~S(\n)
  defp escape_char(?\t), do: ~S(\t)
  defp escape_char(?\r), do: ~S(\r)
  defp escape_char(0x85), do: ~S(\N)
  defp escape_char(0x2028), do: ~S(\L)
  defp escape_char(0x2029), do: ~S(\P)

  # Other escapes are built at compile time
  for c <- Enum.concat([0..0x1F, [0x7F], 0x80..0x9F]), c not in [?\n, ?\t, ?\r, 0x85] do
    defp escape_char(unquote(c)),
      do: unquote("\\x" <> String.pad_leading(Integer.to_string(c, 16), 2, "0"))
  end

  for c <- [0xFEFF, 0xFFFE, 0xFFFF] do
    defp escape_char(unquote(c)), do: unquote("\\u" <> Integer.to_string(c, 16))
  end

  defp utf8_size(c) when c < 0x800, do: 2
  defp utf8_size(c) when c < 0x10000, do: 3
  defp utf8_size(_c), do: 4
end
