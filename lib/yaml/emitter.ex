defmodule YAML.Emitter do
  @moduledoc false

  alias YAML.AST.{Scalar, List, Mapping}
  alias YAML.EncodeError

  @indent_width 2

  # Plain strings YAML would read as another type, or as a merge or value key
  @reserved ~w(
    true True TRUE false False FALSE null Null NULL ~
    yes Yes YES no No NO on On ON off Off OFF y Y n N << =
  )

  # Characters that must be escaped in a double-quoted string
  defguardp is_escaped_byte(c) when c < 0x20 or c == 0x7F

  defguardp is_escaped_char(c)
            when c in 0x80..0x9F or c in [0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF]

  @spec emit(%Scalar{} | %List{} | %Mapping{}) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def emit(node) do
    {:ok, emit_node(node, 0)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  # Walkers
  # -------

  defp emit_node(%Scalar{value: value}, _level), do: write_scalar(value)
  defp emit_node(%Mapping{pairs: []}, _level), do: "{}"
  defp emit_node(%Mapping{pairs: pairs}, level), do: emit_pairs(pairs, level, indent(level))
  defp emit_node(%List{items: []}, _level), do: "[]"
  defp emit_node(%List{items: items}, level), do: emit_items(items, level, indent(level))

  defp emit_node(node, _level),
    do: throw({:encode_error, EncodeError.unsupported(node, "invalid AST node")})

  # The first line takes `first_indent`, so it can follow "- " on the same line
  defp emit_pairs([first | rest], level, first_indent) do
    line_indent = indent(level)
    [emit_pair(first, level, first_indent) | Enum.map(rest, &emit_pair(&1, level, line_indent))]
  end

  defp emit_pair({%Scalar{value: step} = key, value}, level, line_indent),
    do: [line_indent, emit_node(key, 0), ?:, emit_value_at(value, level + 1, step)]

  defp emit_pair({%List{} = key, _value}, _level, _line_indent),
    do: throw({:encode_error, EncodeError.invalid_key(key, "list")})

  defp emit_pair({%Mapping{} = key, _value}, _level, _line_indent),
    do: throw({:encode_error, EncodeError.invalid_key(key, "map")})

  defp emit_pair({key, _value}, _level, _line_indent),
    do: throw({:encode_error, EncodeError.invalid_key(key, "invalid AST node")})

  defp emit_items([first | rest], level, first_indent) do
    line_indent = indent(level)
    [emit_item(first, level, first_indent, 0) | emit_next_items(rest, level, line_indent, 1)]
  end

  defp emit_next_items([item | rest], level, line_indent, index) do
    [
      emit_item(item, level, line_indent, index)
      | emit_next_items(rest, level, line_indent, index + 1)
    ]
  end

  defp emit_next_items([], _level, _line_indent, _index), do: []

  defp emit_item(item, level, line_indent, index),
    do: [line_indent, "- ", emit_item_value_at(item, level + 1, index)]

  # Add the map key or list index to the location of an error from inside the value
  defp emit_value_at(value, level, step) do
    emit_value(value, level)
  catch
    {:encode_error, error} -> throw({:encode_error, EncodeError.prepend_location(error, step)})
  end

  defp emit_item_value_at(item, level, index) do
    emit_item_value(item, level)
  catch
    {:encode_error, error} -> throw({:encode_error, EncodeError.prepend_location(error, index)})
  end

  # Scalars and empty collections stay on the key's line, others start on the next
  defp emit_value(%Scalar{} = node, level), do: [?\s, emit_scalar_value(node, level)]
  defp emit_value(%Mapping{pairs: []}, _level), do: " {}\n"
  defp emit_value(%List{items: []}, _level), do: " []\n"
  defp emit_value(node, level), do: [?\n, emit_node(node, level)]

  # Everything after "- " starts on the same line
  defp emit_item_value(%Scalar{} = node, level), do: emit_scalar_value(node, level)
  defp emit_item_value(%Mapping{pairs: []}, _level), do: "{}\n"
  defp emit_item_value(%List{items: []}, _level), do: "[]\n"
  defp emit_item_value(%Mapping{pairs: pairs}, level), do: emit_pairs(pairs, level, "")
  defp emit_item_value(%List{items: items}, level), do: emit_items(items, level, "")
  defp emit_item_value(node, level), do: emit_node(node, level)

  # Multi-line strings become block scalars; everything else stays on one line
  defp emit_scalar_value(%Scalar{value: value} = node, level) do
    if is_binary(value) and block?(value),
      do: write_block(value, level),
      else: [emit_node(node, 0), ?\n]
  end

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

  # Block scalars
  # -------------

  # The newline check is a fast exit for single-line strings
  defp block?(str) do
    :binary.match(str, "\n") != :nomatch and not indented_start?(str) and
      block_safe?(str, false, false)
  end

  # A block's indentation comes from its first text line, so that line can't start with a space
  defp indented_start?(<<?\n, rest::binary>>), do: indented_start?(rest)
  defp indented_start?(<<?\s, _::binary>>), do: true
  defp indented_start?(_str), do: false

  # One pass: no escaped characters, and some text after a newline
  defp block_safe?(<<?\n, rest::binary>>, multi, _newline), do: block_safe?(rest, multi, true)

  defp block_safe?(<<?\t, rest::binary>>, multi, newline),
    do: block_safe?(rest, multi or newline, newline)

  defp block_safe?(<<c, _::binary>>, _multi, _newline) when is_escaped_byte(c), do: false

  defp block_safe?(<<c, rest::binary>>, multi, newline) when c < 0x80,
    do: block_safe?(rest, multi or newline, newline)

  defp block_safe?(<<c::utf8, _::binary>>, _multi, _newline) when is_escaped_char(c), do: false

  defp block_safe?(<<_::utf8, rest::binary>>, multi, newline),
    do: block_safe?(rest, multi or newline, newline)

  defp block_safe?(<<>>, multi, _newline), do: multi
  defp block_safe?(_invalid, _multi, _newline), do: false

  defp write_block(str, level) do
    body = String.trim_trailing(str, "\n")
    newlines = byte_size(str) - byte_size(body)
    lines = :binary.split(body, "\n", [:global])

    [chomp(newlines), ?\n, Enum.map(lines, &block_line(&1, level)), extra_newlines(newlines)]
  end

  defp chomp(0), do: "|-"
  defp chomp(1), do: "|"
  defp chomp(_newlines), do: "|+"

  defp block_line("", _level), do: ?\n
  defp block_line(line, level), do: [indent(level), line, ?\n]

  defp extra_newlines(newlines) when newlines > 1, do: :binary.copy("\n", newlines - 1)
  defp extra_newlines(_newlines), do: []

  # Indentation
  # -----------

  for level <- 0..32 do
    defp indent(unquote(level)), do: unquote(String.duplicate(" ", level * @indent_width))
  end

  defp indent(level), do: :binary.copy(" ", level * @indent_width)
end
