defmodule YAML.Encode do
  @moduledoc false

  alias YAML.AST.{Document, List, Mapping, Scalar}
  alias YAML.EncodeError

  @indent_width 2

  @reserved_words ~w(true false null yes no on off y n)

  @reserved_symbols ~w(~ << =)

  @value_atoms [nil, true, false, :"+inf", :"-inf", :nan]

  defguardp is_scalar_key(key)
            when is_binary(key) or is_atom(key) or is_number(key) or is_struct(key, Date) or
                   is_struct(key, Time) or is_struct(key, NaiveDateTime) or
                   is_struct(key, DateTime)

  defguardp is_plain_map(term) when is_map(term) and not is_struct(term)

  defguardp is_encoded_struct(term)
            when is_struct(term) and not is_struct(term, Date) and not is_struct(term, Time) and
                   not is_struct(term, NaiveDateTime) and not is_struct(term, DateTime)

  defguardp is_escaped_byte(c) when c < 0x20 or c == 0x7F

  defguardp is_escaped_char(c)
            when c in 0x80..0x9F or c in [0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF]

  @spec data(term(), boolean()) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def data(term, sort \\ false) do
    {:ok, ["---\n", data_root(term, sort)]}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  @spec document(Document.t()) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def document(%Document{} = document) do
    {:ok, ast_document(document)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  @spec documents([Document.t()]) :: {:ok, iodata()} | {:error, EncodeError.t()}
  def documents(documents) when is_list(documents) do
    {:ok, ast_documents(documents, 0)}
  catch
    {:encode_error, %EncodeError{} = error} -> {:error, error}
  end

  defp fail(error), do: throw({:encode_error, error})

  defp data_root(map, _sort) when map == %{}, do: "{}\n"
  defp data_root([], _sort), do: "[]\n"
  defp data_root(map, sort) when is_plain_map(map), do: data_pairs(map, 0, "", sort)
  defp data_root(list, sort) when is_list(list), do: data_items(list, 0, "", sort)

  defp data_root(struct, sort) when is_encoded_struct(struct),
    do: data_root(encode_struct(struct), sort)

  defp data_root(value, _sort), do: write_value(value, 1)

  defp encode_struct(struct) do
    YAML.Encoder.encode(struct)
  rescue
    error in Protocol.UndefinedError ->
      if error.protocol == YAML.Encoder and error.value === struct,
        do: fail(EncodeError.unsupported(struct, "#{type_name(struct)} without a YAML.Encoder")),
        else: reraise(error, __STACKTRACE__)
  end

  defp data_pairs(map, level, first_indent, sort) do
    [first | rest] = map_pairs(map, sort)

    line_indent = if rest == [], do: "", else: indent(level)

    [
      data_pair(first, map, level, first_indent, sort)
      | Enum.map(rest, &data_pair(&1, map, level, line_indent, sort))
    ]
  end

  defp data_pair({key, value}, map, level, line_indent, sort) when is_scalar_key(key) do
    text = key_text(key, map)
    written_key = write_scalar(text)

    written =
      try do
        data_value(value, level + 1, sort)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key))
      end

    pair_line(text, written_key, written, level, line_indent)
  end

  defp data_pair({key, value}, _map, level, line_indent, sort)
       when is_plain_map(key) or is_list(key) do
    written_key = data_item_value(key, level + 1, sort)

    [line_indent, "? ", written_key, indent(level), ?: | data_value(value, level + 1, sort)]
  catch
    {:encode_error, error} ->
      fail(EncodeError.prepend_location(error, key))
  end

  defp data_pair({key, _value}, _map, _level, _line_indent, _sort),
    do: fail(EncodeError.invalid_key(key, type_name(key)))

  defp pair_line(text, written_key, written, level, line_indent) do
    if is_binary(text) and byte_size(text) > 255 and IO.iodata_length(written_key) > 1024,
      do: [line_indent, "? ", written_key, ?\n, indent(level), ?: | written],
      else: [line_indent, written_key, ?: | written]
  end

  defp key_text(key, map) do
    text = as_text(key)
    if text !== key and is_map_key(map, text), do: fail(EncodeError.duplicate_key(key))
    text
  end

  defp map_pairs(map, false), do: Map.to_list(map)

  defp map_pairs(map, true),
    do: map |> Map.to_list() |> Enum.sort_by(fn {key, _value} -> as_text(key) end)

  defp data_items([first | rest], level, first_indent, sort) do
    line_indent = if rest == [], do: "", else: indent(level)

    [
      data_item(first, level, first_indent, 0, sort)
      | data_next_items(rest, level, line_indent, 1, sort)
    ]
  end

  defp data_next_items([item | rest], level, line_indent, index, sort) do
    [
      data_item(item, level, line_indent, index, sort)
      | data_next_items(rest, level, line_indent, index + 1, sort)
    ]
  end

  defp data_next_items([], _level, _line_indent, _index, _sort), do: []

  defp data_item(item, level, line_indent, index, sort) do
    [line_indent, "- " | data_item_value(item, level + 1, sort)]
  catch
    {:encode_error, error} ->
      fail(EncodeError.prepend_location(error, index))
  end

  defp data_value(map, _level, _sort) when map == %{}, do: " {}\n"
  defp data_value([], _level, _sort), do: " []\n"

  defp data_value(map, level, sort) when is_plain_map(map),
    do: [?\n | data_pairs(map, level, indent(level), sort)]

  defp data_value(list, level, sort) when is_list(list),
    do: [?\n | data_items(list, level, indent(level), sort)]

  defp data_value(struct, level, sort) when is_encoded_struct(struct),
    do: data_value(encode_struct(struct), level, sort)

  defp data_value(value, level, _sort), do: [?\s | write_value(value, level)]

  defp data_item_value(map, _level, _sort) when map == %{}, do: "{}\n"
  defp data_item_value([], _level, _sort), do: "[]\n"

  defp data_item_value(map, level, sort) when is_plain_map(map),
    do: data_pairs(map, level, "", sort)

  defp data_item_value(list, level, sort) when is_list(list),
    do: data_items(list, level, "", sort)

  defp data_item_value(struct, level, sort) when is_encoded_struct(struct),
    do: data_item_value(encode_struct(struct), level, sort)

  defp data_item_value(value, level, _sort), do: write_value(value, level)

  defp ast_documents([%Document{} = document | rest], index) do
    written =
      try do
        ast_document(document)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, index))
      end

    [written | ast_documents(rest, index + 1)]
  end

  defp ast_documents([], _index), do: []

  defp ast_document(%Document{root: root}), do: ["---\n", ast_root(root)]

  defp ast_root(%Scalar{value: value}), do: write_value(value, 1)
  defp ast_root(%Mapping{pairs: []}), do: "{}\n"
  defp ast_root(%List{items: []}), do: "[]\n"
  defp ast_root(node), do: ast_node(node, 0)

  defp ast_node(%Mapping{pairs: pairs}, level), do: ast_pairs(pairs, level, indent(level))
  defp ast_node(%List{items: items}, level), do: ast_items(items, level, indent(level))

  defp ast_pairs([first | rest], level, first_indent) do
    line_indent = if rest == [], do: "", else: indent(level)
    [ast_pair(first, level, first_indent) | Enum.map(rest, &ast_pair(&1, level, line_indent))]
  end

  defp ast_pair({%Scalar{value: key_value}, value}, level, line_indent)
       when is_scalar_key(key_value) do
    text = as_text(key_value)
    written_key = write_scalar(text)

    written =
      try do
        ast_value(value, level + 1)
      catch
        {:encode_error, error} ->
          fail(EncodeError.prepend_location(error, key_value))
      end

    pair_line(text, written_key, written, level, line_indent)
  end

  defp ast_pair({%type{} = key, value}, level, line_indent) when type in [List, Mapping] do
    written_key = ast_item_value(key, level + 1)

    [line_indent, "? ", written_key, indent(level), ?: | ast_value(value, level + 1)]
  catch
    {:encode_error, error} ->
      fail(EncodeError.prepend_location(error, key))
  end

  defp ast_items([first | rest], level, first_indent) do
    line_indent = if rest == [], do: "", else: indent(level)
    [ast_item(first, level, first_indent, 0) | ast_next_items(rest, level, line_indent, 1)]
  end

  defp ast_next_items([item | rest], level, line_indent, index) do
    [
      ast_item(item, level, line_indent, index)
      | ast_next_items(rest, level, line_indent, index + 1)
    ]
  end

  defp ast_next_items([], _level, _line_indent, _index), do: []

  defp ast_item(item, level, line_indent, index) do
    [line_indent, "- " | ast_item_value(item, level + 1)]
  catch
    {:encode_error, error} ->
      fail(EncodeError.prepend_location(error, index))
  end

  defp ast_value(%Scalar{value: value}, level), do: [?\s | write_value(value, level)]
  defp ast_value(%Mapping{pairs: []}, _level), do: " {}\n"
  defp ast_value(%List{items: []}, _level), do: " []\n"
  defp ast_value(node, level), do: [?\n | ast_node(node, level)]

  defp ast_item_value(%Scalar{value: value}, level), do: write_value(value, level)
  defp ast_item_value(%Mapping{pairs: []}, _level), do: "{}\n"
  defp ast_item_value(%List{items: []}, _level), do: "[]\n"
  defp ast_item_value(%Mapping{pairs: pairs}, level), do: ast_pairs(pairs, level, "")
  defp ast_item_value(%List{items: items}, level), do: ast_items(items, level, "")

  defp as_text(atom) when is_atom(atom) and atom not in @value_atoms, do: Atom.to_string(atom)
  defp as_text(%Date{} = date), do: Date.to_iso8601(date)
  defp as_text(%Time{} = time), do: Time.to_iso8601(time)
  defp as_text(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp as_text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp as_text(value), do: value

  defp write_value("", _level), do: [~s(""), ?\n]

  defp write_value(text, level) when is_binary(text) do
    cond do
      plain_chars?(text) ->
        [if(reserved?(text) or quote_start?(text), do: quoted(text), else: text), ?\n]

      :binary.match(text, "\n") != :nomatch and not indented_start?(text) and
          block_safe?(text, false, false) ->
        body = String.trim_trailing(text, "\n")
        newlines = byte_size(text) - byte_size(body)
        chomp = Enum.at(["|-", "|"], newlines, "|+")
        extra = [:binary.copy("\n", max(newlines - 1, 0))]
        [chomp, ?\n | block_lines(:binary.split(body, "\n", [:global]), indent(level), extra)]

      true ->
        [quoted(text), ?\n]
    end
  end

  defp write_value(atom, level) when is_atom(atom) and atom not in @value_atoms,
    do: write_value(Atom.to_string(atom), level)

  defp write_value(value, _level), do: [write_scalar(value), ?\n]

  defp block_lines(["" | lines], line_indent, extra),
    do: [?\n | block_lines(lines, line_indent, extra)]

  defp block_lines([line | lines], line_indent, extra),
    do: [line_indent, line, ?\n | block_lines(lines, line_indent, extra)]

  defp block_lines([], _line_indent, extra), do: extra

  defp write_scalar(:"+inf"), do: ".inf"
  defp write_scalar(:"-inf"), do: "-.inf"
  defp write_scalar(:nan), do: ".nan"

  defp write_scalar(nil), do: "null"
  defp write_scalar(bool) when is_boolean(bool), do: Atom.to_string(bool)
  defp write_scalar(int) when is_integer(int), do: Integer.to_string(int)

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
      do: quoted(str),
      else: str
  end

  defp write_scalar(%type{} = value) when type in [Date, Time, NaiveDateTime, DateTime],
    do: write_scalar(as_text(value))

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

  defp indented_start?(<<?\n, rest::binary>>), do: indented_start?(rest)
  defp indented_start?(<<c, _::binary>>) when c in [?\s, ?\t], do: true
  defp indented_start?(_str), do: false

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

  for level <- 0..32 do
    defp indent(unquote(level)), do: unquote(String.duplicate(" ", level * @indent_width))
  end

  defp indent(level), do: :binary.copy(" ", level * @indent_width)
end
