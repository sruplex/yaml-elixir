defmodule YAML.Encode do
  @moduledoc false

  alias YAML.AST.Scalar
  alias YAML.EncodeError

  # Plain words YAML would read as another type, in any letter case
  @reserved_words ~w(true false null yes no on off y n)

  # Plain strings YAML would read as null, or as a merge or value key
  @reserved_symbols ~w(~ << =)

  # Characters that must be escaped in a double-quoted string
  defguardp is_escaped_byte(c) when c < 0x20 or c == 0x7F

  defguardp is_escaped_char(c)
            when c in 0x80..0x9F or c in [0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF]

  @spec data(term()) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def data(term) do
    {:ok, write_scalar(term)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  @spec node(%Scalar{}) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def node(%Scalar{value: value}) do
    {:ok, write_scalar(value)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  # Errors are thrown inside the walk and returned by the public functions
  defp fail(error), do: throw({:encode_error, error})

  # Writers
  # -------

  # Decode returns .inf, -.inf and .nan as these atoms
  defp write_scalar(:"+inf"), do: ".inf"
  defp write_scalar(:"-inf"), do: "-.inf"
  defp write_scalar(:nan), do: ".nan"

  defp write_scalar(nil), do: "null"
  defp write_scalar(bool) when is_boolean(bool), do: Atom.to_string(bool)
  defp write_scalar(int) when is_integer(int), do: Integer.to_string(int)

  # YAML 1.1 needs a sign in the exponent: 1.0e+20
  defp write_scalar(float) when is_float(float) do
    string = Float.to_string(float)

    case :binary.split(string, "e") do
      [mantissa, "-" <> _ = exponent] -> [mantissa, ?e, exponent]
      [mantissa, exponent] -> [mantissa, "e+", exponent]
      [_] -> string
    end
  end

  defp write_scalar(""), do: ~s("")

  defp write_scalar(str) when is_binary(str) do
    if reserved?(str) or quote_start?(str) or not plain_chars?(str),
      do: [?", escape(str, str, 0, 0), ?"],
      else: str
  end

  defp write_scalar(atom) when is_atom(atom), do: write_scalar(Atom.to_string(atom))

  defp write_scalar(%Date{} = date), do: write_scalar(Date.to_iso8601(date))
  defp write_scalar(%Time{} = time), do: write_scalar(Time.to_iso8601(time))

  defp write_scalar(%NaiveDateTime{} = datetime),
    do: write_scalar(NaiveDateTime.to_iso8601(datetime))

  defp write_scalar(%DateTime{} = datetime), do: write_scalar(DateTime.to_iso8601(datetime))

  defp write_scalar(value),
    do: fail(EncodeError.unsupported(value, type_name(value)))

  defp type_name(%module{}), do: "#{inspect(module)} struct"
  defp type_name(term) when is_tuple(term), do: "tuple"
  defp type_name(term) when is_pid(term), do: "pid"
  defp type_name(term) when is_reference(term), do: "reference"
  defp type_name(term) when is_function(term), do: "function"
  defp type_name(term) when is_port(term), do: "port"
  defp type_name(term) when is_bitstring(term), do: "bitstring"
  defp type_name(term) when is_list(term), do: "list"
  defp type_name(term) when is_map(term), do: "map"

  # Strings
  # -------

  # Every letter case of each word, built at compile time
  for word <- @reserved_words do
    variants =
      Enum.reduce(String.graphemes(word), [""], fn c, acc ->
        for start <- acc, letter <- [String.downcase(c), String.upcase(c)], do: start <> letter
      end)

    for variant <- variants do
      defp reserved?(unquote(variant)), do: true
    end
  end

  for symbol <- @reserved_symbols do
    defp reserved?(unquote(symbol)), do: true
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

  # Copies runs of safe bytes as slices of the original string
  defp escape(<<c, rest::binary>>, str, skip, 0) when c in [?", ?\\] or is_escaped_byte(c),
    do: [escape_char(c) | escape(rest, str, skip + 1, 0)]

  defp escape(<<c, rest::binary>>, str, skip, len) when c in [?", ?\\] or is_escaped_byte(c),
    do: [binary_part(str, skip, len), escape_char(c) | escape(rest, str, skip + len + 1, 0)]

  defp escape(<<c, rest::binary>>, str, skip, len) when c < 0x80,
    do: escape(rest, str, skip, len + 1)

  defp escape(<<c::utf8, rest::binary>>, str, skip, 0) when is_escaped_char(c),
    do: [escape_char(c) | escape(rest, str, skip + utf8_size(c), 0)]

  defp escape(<<c::utf8, rest::binary>>, str, skip, len) when is_escaped_char(c) do
    size = utf8_size(c)
    [binary_part(str, skip, len), escape_char(c) | escape(rest, str, skip + len + size, 0)]
  end

  defp escape(<<c::utf8, rest::binary>>, str, skip, len),
    do: escape(rest, str, skip, len + utf8_size(c))

  defp escape(<<>>, _str, _skip, 0), do: []
  defp escape(<<>>, str, skip, len), do: [binary_part(str, skip, len)]

  defp escape(_invalid, str, _skip, _len),
    do: fail(EncodeError.invalid_utf8(str))

  defp escape_char(?"), do: ~S(\")
  defp escape_char(?\\), do: ~S(\\)
  defp escape_char(?\n), do: ~S(\n)
  defp escape_char(?\t), do: ~S(\t)
  defp escape_char(?\r), do: ~S(\r)
  defp escape_char(0x85), do: ~S(\N)
  defp escape_char(0x2028), do: ~S(\L)
  defp escape_char(0x2029), do: ~S(\P)

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
