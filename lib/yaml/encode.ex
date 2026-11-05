defmodule YAML.Encode do
  @moduledoc false

  alias YAML.AST.{Scalar, List, Mapping}
  alias YAML.EncodeError

  @indent_width 2

  # Plain words YAML would read as another type; some parsers ignore their letter case
  @reserved_words ~w(true false null yes no on off y n)

  # Plain strings YAML would read as null, or as a merge or value key
  @reserved_symbols ~w(~ << =)

  # Atoms written as YAML values instead of as their names
  @value_atoms [nil, true, false, :"+inf", :"-inf", :nan]

  # Scalars written as a plain "key:"; maps and lists use the explicit "? key" form
  defguardp is_key(key)
            when is_binary(key) or is_atom(key) or is_number(key) or is_struct(key, Date) or
                   is_struct(key, Time) or is_struct(key, NaiveDateTime) or
                   is_struct(key, DateTime)

  # Characters that must be escaped in a double-quoted string
  defguardp is_escaped_byte(c) when c < 0x20 or c == 0x7F

  defguardp is_escaped_char(c)
            when c in 0x80..0x9F or c in [0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF]

  @spec data(term()) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def data(term) do
    written =
      case term do
        map when map == %{} -> "{}"
        [] -> "[]"
        map when is_map(map) and not is_struct(map) -> data_pairs(map, 0, "")
        list when is_list(list) -> data_items(list, 0, "")
        value -> write_scalar(value)
      end

    {:ok, written}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  @spec node(%Scalar{} | %List{} | %Mapping{}) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def node(node) do
    {:ok, ast_node(node, 0)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  # Plain data
  # ----------

  # The first line takes `first_indent`, so it can follow "- " on the same line
  defp data_pairs(map, level, first_indent) do
    [first | rest] = Map.to_list(map)

    # Built only when a second line needs it, so deep single-item nesting stays cheap
    line_indent = if rest == [], do: "", else: indent(level)

    [
      data_pair(first, map, level, first_indent)
      | Enum.map(rest, &data_pair(&1, map, level, line_indent))
    ]
  end

  # Adds the map key to the location of an error from inside the value
  defp data_pair({key, value}, map, level, line_indent) when is_key(key) do
    written_key =
      if is_atom(key) and key not in @value_atoms do
        # An atom key and a string key with the same text would be written as the same key
        text = Atom.to_string(key)
        if is_map_key(map, text), do: fail(EncodeError.duplicate_key(key))
        write_scalar(text)
      else
        write_scalar(key)
      end

    written =
      try do
        data_value(value, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key))
      end

    pair_line(key, written_key, written, level, line_indent)
  end

  # Map and list keys use the explicit "? key" form, with the value on the ":" line
  defp data_pair({key, value}, _map, level, line_indent)
       when (is_map(key) and not is_struct(key)) or is_list(key) do
    written_key = data_item_value(key, level + 1)

    written =
      try do
        data_value(value, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key))
      end

    [line_indent, "? ", written_key, indent(level), ?: | written]
  end

  defp data_pair({key, _value}, _map, _level, _line_indent),
    do: fail(EncodeError.invalid_key(key, type_name(key)))

  # Tagged, since libyaml-based parsers merge a "<<" key even when it's quoted
  defp pair_line(key, _written_key, written, _level, line_indent) when key in ["<<", :"<<"],
    do: [line_indent, ~s(!!str "<<":) | written]

  # Keys written past YAML's 1024 limit become "? key"; under 256 bytes they can't reach it
  defp pair_line(key, written_key, written, level, line_indent) do
    if is_binary(key) and byte_size(key) > 255 and IO.iodata_length(written_key) > 1024,
      do: [line_indent, "? ", written_key, ?\n, indent(level), ?: | written],
      else: [line_indent, written_key, ?: | written]
  end

  defp data_items([first | rest], level, first_indent) do
    # Built only when a second line needs it, so deep single-item nesting stays cheap
    line_indent = if rest == [], do: "", else: indent(level)
    [data_item(first, level, first_indent, 0) | data_next_items(rest, level, line_indent, 1)]
  end

  defp data_next_items([item | rest], level, line_indent, index) do
    [
      data_item(item, level, line_indent, index)
      | data_next_items(rest, level, line_indent, index + 1)
    ]
  end

  defp data_next_items([], _level, _line_indent, _index), do: []

  defp data_next_items(tail, _level, _line_indent, _index),
    do: fail(EncodeError.unsupported(tail, "improper list"))

  # Adds the list index to the location of an error from inside the item
  defp data_item(item, level, line_indent, index) do
    written =
      try do
        data_item_value(item, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, index))
      end

    [line_indent, "- " | written]
  end

  # Scalars and empty collections stay on the key's line, others start on the next
  defp data_value(map, _level) when map == %{}, do: " {}\n"
  defp data_value([], _level), do: " []\n"

  defp data_value(map, level) when is_map(map) and not is_struct(map),
    do: [?\n | data_pairs(map, level, indent(level))]

  defp data_value(list, level) when is_list(list),
    do: [?\n | data_items(list, level, indent(level))]

  defp data_value(value, _level), do: [?\s, write_scalar(value), ?\n]

  # Everything after "- " starts on the same line
  defp data_item_value(map, _level) when map == %{}, do: "{}\n"
  defp data_item_value([], _level), do: "[]\n"

  defp data_item_value(map, level) when is_map(map) and not is_struct(map),
    do: data_pairs(map, level, "")

  defp data_item_value(list, level) when is_list(list), do: data_items(list, level, "")
  defp data_item_value(value, _level), do: [write_scalar(value), ?\n]

  # YAML AST
  # --------

  defp ast_node(%Scalar{value: value}, _level), do: write_scalar(value)
  defp ast_node(%Mapping{pairs: []}, _level), do: "{}"
  defp ast_node(%Mapping{pairs: pairs}, level), do: ast_pairs(pairs, level, indent(level))
  defp ast_node(%List{items: []}, _level), do: "[]"
  defp ast_node(%List{items: items}, level), do: ast_items(items, level, indent(level))

  defp ast_node(node, _level),
    do: fail(EncodeError.unsupported(node, "invalid AST node"))

  # The first line takes `first_indent`, so it can follow "- " on the same line
  defp ast_pairs([first | rest], level, first_indent) do
    # Built only when a second line needs it, so deep single-item nesting stays cheap
    line_indent = if rest == [], do: "", else: indent(level)
    [ast_pair(first, level, first_indent) | ast_next_pairs(rest, level, line_indent)]
  end

  defp ast_pairs(pairs, _level, _first_indent),
    do: fail(EncodeError.unsupported(pairs, "invalid AST node"))

  defp ast_next_pairs([pair | rest], level, line_indent),
    do: [ast_pair(pair, level, line_indent) | ast_next_pairs(rest, level, line_indent)]

  defp ast_next_pairs([], _level, _line_indent), do: []

  defp ast_next_pairs(tail, _level, _line_indent),
    do: fail(EncodeError.unsupported(tail, "improper list"))

  # Adds the map key to the location of an error from inside the value
  defp ast_pair({%Scalar{value: key_value}, value}, level, line_indent)
       when is_key(key_value) do
    written_key = write_scalar(key_value)

    written =
      try do
        ast_value(value, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key_value))
      end

    pair_line(key_value, written_key, written, level, line_indent)
  end

  defp ast_pair({%Scalar{value: key_value}, _value}, _level, _line_indent),
    do: fail(EncodeError.invalid_key(key_value, type_name(key_value)))

  # Map and list keys use the explicit "? key" form, with the value on the ":" line
  defp ast_pair({%type{} = key, value}, level, line_indent) when type in [List, Mapping] do
    written_key = ast_item_value(key, level + 1)

    written =
      try do
        ast_value(value, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key))
      end

    [line_indent, "? ", written_key, indent(level), ?: | written]
  end

  defp ast_pair({key, _value}, _level, _line_indent),
    do: fail(EncodeError.invalid_key(key, "invalid AST node"))

  defp ast_pair(pair, _level, _line_indent),
    do: fail(EncodeError.unsupported(pair, "invalid AST node"))

  defp ast_items([first | rest], level, first_indent) do
    # Built only when a second line needs it, so deep single-item nesting stays cheap
    line_indent = if rest == [], do: "", else: indent(level)
    [ast_item(first, level, first_indent, 0) | ast_next_items(rest, level, line_indent, 1)]
  end

  defp ast_items(items, _level, _first_indent),
    do: fail(EncodeError.unsupported(items, "invalid AST node"))

  defp ast_next_items([item | rest], level, line_indent, index) do
    [
      ast_item(item, level, line_indent, index)
      | ast_next_items(rest, level, line_indent, index + 1)
    ]
  end

  defp ast_next_items([], _level, _line_indent, _index), do: []

  defp ast_next_items(tail, _level, _line_indent, _index),
    do: fail(EncodeError.unsupported(tail, "improper list"))

  # Adds the list index to the location of an error from inside the item
  defp ast_item(item, level, line_indent, index) do
    written =
      try do
        ast_item_value(item, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, index))
      end

    [line_indent, "- " | written]
  end

  # Scalars and empty collections stay on the key's line, others start on the next
  defp ast_value(%Scalar{} = node, _level), do: [?\s, ast_node(node, 0), ?\n]
  defp ast_value(%Mapping{pairs: []}, _level), do: " {}\n"
  defp ast_value(%List{items: []}, _level), do: " []\n"
  defp ast_value(node, level), do: [?\n | ast_node(node, level)]

  # Everything after "- " starts on the same line
  defp ast_item_value(%Scalar{} = node, _level), do: [ast_node(node, 0), ?\n]
  defp ast_item_value(%Mapping{pairs: []}, _level), do: "{}\n"
  defp ast_item_value(%List{items: []}, _level), do: "[]\n"
  defp ast_item_value(%Mapping{pairs: pairs}, level), do: ast_pairs(pairs, level, "")
  defp ast_item_value(%List{items: items}, level), do: ast_items(items, level, "")
  defp ast_item_value(node, level), do: ast_node(node, level)

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

  # Dates and times are written as ISO 8601 text
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
  defp type_name(_term), do: "term"

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
    do: fail(EncodeError.invalid_utf8(str))

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

  # Indentation
  # -----------

  for level <- 0..32 do
    defp indent(unquote(level)), do: unquote(String.duplicate(" ", level * @indent_width))
  end

  defp indent(level), do: :binary.copy(" ", level * @indent_width)
end
