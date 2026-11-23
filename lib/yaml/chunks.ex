defmodule YAML.Chunks do
  @moduledoc false

  alias YAML.AST
  alias YAML.ParsingError

  @chunk_size 262_144
  @workers 4

  @spec stream(
          Enumerable.t(),
          (binary() -> {:ok, list()} | {:error, ParsingError.t()}),
          keyword()
        ) ::
          Enumerable.t()
  def stream(enumerable, decode, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @chunk_size)
    # Joined documents move an empty document's null to another line
    join_size = if opts[:detailed], do: 0, else: chunk_size

    enumerable
    |> pieces({chunk_size, join_size})
    |> Task.async_stream(&decode_piece(&1, decode),
      max_concurrency: min(@workers, System.schedulers_online()),
      ordered: true,
      timeout: :infinity
    )
    |> Stream.transform(false, fn {:ok, results}, failed ->
      Enum.flat_map_reduce(results, failed, &result/2)
    end)
  end

  defp result({_continued, {:raise, kind, reason, stacktrace}}, _failed),
    do: :erlang.raise(kind, reason, stacktrace)

  defp result({true, {:ok, [_]}}, true), do: {[], true}
  defp result({true, {:ok, [_ | data]}}, true), do: {data, false}
  defp result({true, {:error, _error}}, true), do: {[], true}
  defp result({_continued, {:ok, data}}, _failed), do: {data, false}
  defp result({_continued, {:error, _error} = error}, _failed), do: {[error], true}

  defp decode_piece({line, text, continued}, decode) do
    text = IO.iodata_to_binary(text)

    case decode.(text) do
      {:ok, data} ->
        [{continued, {:ok, Enum.map(data, &{:ok, shift(&1, line - 1)})}}]

      {:error, error} ->
        decode_each(text, error, line, continued, decode)
    end
  catch
    kind, reason -> [{false, {:raise, kind, reason, __STACKTRACE__}}]
  end

  defp decode_each(text, error, line, continued, decode) do
    case [text] |> pieces({byte_size(text) + 1, 0}) |> Enum.to_list() do
      [_document] ->
        [{continued, {:error, at(error, line)}}]

      documents ->
        documents
        |> Enum.with_index()
        |> Enum.flat_map(fn {{at, text, _continued}, index} ->
          decode_piece({line + at - 1, text, continued and index == 0}, decode)
        end)
    end
  end

  defp shift(data, 0), do: data
  defp shift(%AST.Document{root: root} = document, by), do: %{document | root: shift(root, by)}

  defp shift(%AST.Mapping{pairs: pairs, meta: meta} = mapping, by),
    do: %{
      mapping
      | pairs: Enum.map(pairs, fn {key, value} -> {shift(key, by), shift(value, by)} end),
        meta: moved(meta, by)
    }

  defp shift(%AST.List{items: items, meta: meta} = list, by),
    do: %{list | items: Enum.map(items, &shift(&1, by)), meta: moved(meta, by)}

  defp shift(%AST.Scalar{meta: meta} = scalar, by), do: %{scalar | meta: moved(meta, by)}
  defp shift(data, _by), do: data

  defp moved(%AST.Meta{line: line} = meta, by) when is_integer(line),
    do: %{meta | line: line + by}

  defp moved(meta, _by), do: meta

  defp at(%ParsingError{location: {at, column}} = error, line),
    do: %{error | location: {at + line - 1, column}}

  defp pieces(enumerable, sizes) do
    Stream.transform(
      enumerable,
      fn -> {"", new(1)} end,
      fn chunk, {rest, piece} ->
        text = rest <> chunk
        ends = :binary.matches(text, "\n", scope: {byte_size(rest), byte_size(chunk)})
        {done, piece, from} = scan(ends, 0, piece, nil, {text, sizes}, [])
        {done, {binary_part(text, from, byte_size(text) - from), piece}}
      end,
      fn {rest, piece} ->
        {done, piece} = if rest == "", do: {[], piece}, else: add(rest, piece, sizes)
        {done ++ document(piece), {"", new(1)}}
      end,
      fn _acc -> :ok end
    )
  end

  defp scan([], from, piece, run, {text, _sizes}, done),
    do: {Enum.reverse(done), flush(piece, run, text), from}

  defp scan([{e, 1} | ends] = all, s, piece, run, {text, sizes} = ctx, done) do
    {chunk_size, join_size} = sizes
    first = if e > s, do: :binary.at(text, s)

    cond do
      descend?(piece, run, sizes) ->
        {ready, piece} = descend(flush(piece, run, text))
        scan(all, s, piece, nil, ctx, Enum.reverse(ready, done))

      lazy?(binary_part(text, s, e - s), piece, run, join_size) ->
        piece = %{
          piece
          | kind: :lazy,
            pad: "",
            directives: [],
            stuck: false,
            doc_size: size(piece, run)
        }

        scan(ends, e + 1, piece, keep(run, s, e), ctx, done)

      extends?(first, piece, run, chunk_size) ->
        scan(ends, e + 1, piece, keep(run, s, e), ctx, done)

      true ->
        {ready, piece} = add(binary_part(text, s, e - s), flush(piece, run, text), sizes)
        scan(ends, e + 1, piece, nil, ctx, Enum.reverse(ready, done))
    end
  end

  defp lazy?(line, piece, run, join_size),
    do: line == "---" and piece.begun and piece.key == nil and size(piece, run) < join_size

  defp extends?(first, piece, run, chunk_size) do
    first not in [?-, ?.] and piece.kind != :unknown and
      not (piece.key != nil and column0?(first)) and
      (size(piece, run) - piece.doc_size < chunk_size or indented?(first, piece))
  end

  defp indented?(first, %{pad: ""}), do: not column0?(first)
  defp indented?(_first, _piece), do: false

  defp column0?(first), do: first not in [nil, ?\s, ?\t, ?\r, ?#]

  # An AST would give the repeated key the line before the piece
  defp descend?(piece, run, {chunk_size, join_size}),
    do:
      join_size > 0 and piece.key == nil and not piece.stuck and piece.kind == :map and
        piece.pad == "" and size(piece, run) - piece.doc_size >= 2 * chunk_size

  defp descend(piece) do
    text = piece.lines |> Enum.reverse() |> IO.iodata_to_binary()
    earlier = binary_part(text, 0, piece.doc_size)
    doc = binary_part(text, piece.doc_size, byte_size(text) - piece.doc_size)
    lines = String.split(doc, "\n")
    lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
    at = lines |> Enum.reverse() |> Enum.find_index(&root_key?/1)
    at = at && length(lines) - 1 - at

    with true <- at != nil,
         {before, [key | value]} = Enum.split(lines, at),
         true <- Regex.match?(~r/:[ \t]*(#.*)?\r?$/, key),
         {kind, pad} when kind in [:list, :map] <- value_kind(value) do
      head = Enum.reverse(["---" | piece.directives])
      skipped = earlier |> :binary.matches("\n") |> length()
      part? = Enum.any?(before, &root_key?/1)
      earlier = if part?, do: [earlier | Enum.map(before, &[&1, "\n"])], else: earlier

      earlier =
        if IO.iodata_length(earlier) == 0,
          do: [],
          else: [{piece.start, earlier, piece.continued}]

      next = %{
        lines(%{piece | start: piece.start + skipped + at - length(head)}, head ++ [key | value])
        | kind: kind,
          pad: pad,
          key: key,
          continued: part? or (piece.doc_size == 0 and piece.continued),
          doc_size: 0
      }

      {earlier, next}
    else
      _no -> {[], %{piece | stuck: true}}
    end
  end

  defp root_key?(line),
    do: item?(:map, "", line) and not String.starts_with?(line, ["---", "...", "%"])

  defp value_kind(value) do
    Enum.find_value(value, {:none, ""}, fn line ->
      case String.trim(line) do
        "" ->
          nil

        "#" <> _ ->
          nil

        trimmed ->
          unindented = String.trim_leading(line, " ")

          {kind(unindented, trimmed),
           binary_part(line, 0, byte_size(line) - byte_size(unindented))}
      end
    end)
  end

  defp lines(piece, lines),
    do: %{
      piece
      | lines: lines |> Enum.map(&[&1, "\n"]) |> Enum.reverse(),
        count: length(lines),
        size: Enum.reduce(lines, 0, &(byte_size(&1) + 1 + &2))
    }

  defp keep({:keep, from, _to, count}, _s, e), do: {:keep, from, e + 1, count + 1}
  defp keep(nil, s, e), do: {:keep, s, e + 1, 1}

  defp size(piece, {:keep, from, to, _count}), do: piece.size + to - from
  defp size(piece, nil), do: piece.size

  defp flush(piece, nil, _text), do: piece

  defp flush(piece, {:keep, from, to, count}, text),
    do: %{
      piece
      | lines: [binary_part(text, from, to - from) | piece.lines],
        count: piece.count + count,
        size: piece.size + to - from
    }

  defp finish(piece),
    do: {piece.start, Enum.reverse(piece.lines), piece.continued}

  defp document(%{in_document: false}), do: []
  defp document(piece), do: [finish(piece)]

  defp new(start),
    do: %{
      lines: [],
      count: 0,
      size: 0,
      kind: :unknown,
      pad: "",
      directives: [],
      start: start,
      continued: false,
      in_document: false,
      begun: false,
      key: nil,
      stuck: false,
      doc_size: 0
    }

  defp next_document(piece),
    do: %{
      piece
      | kind: :unknown,
        pad: "",
        directives: [],
        begun: false,
        key: nil,
        stuck: false,
        doc_size: piece.size
    }

  defp add(line, piece, {chunk_size, join_size} = sizes) do
    at = piece.start + piece.count

    cond do
      marker?(line, "---") ->
        start(line, piece, at, join_size)

      marker?(line, "...") ->
        piece = append(line, piece)

        if piece.size >= join_size,
          do: {document(piece), new(at + 1)},
          else: {[], next_document(piece)}

      piece.kind == :lazy ->
        add_lazy(line, piece, sizes)

      piece.kind == :unknown ->
        begun = piece.begun or starts?(line)
        piece = %{piece | in_document: piece.in_document or begun, begun: begun}
        {[], first_line(line, append(line, piece))}

      true ->
        content(line, piece, at, chunk_size)
    end
  end

  defp add_lazy(line, piece, {chunk_size, _join_size} = sizes) do
    if piece.size - piece.doc_size < chunk_size do
      {[], append(line, piece)}
    else
      text = piece.lines |> Enum.reverse() |> IO.iodata_to_binary()
      doc = binary_part(text, piece.doc_size + 4, byte_size(text) - piece.doc_size - 4)

      piece =
        doc
        |> String.split("\n")
        |> Enum.reduce(%{piece | kind: :unknown}, fn
          line, %{kind: :unknown} = piece -> first_line(line, piece)
          _line, piece -> piece
        end)

      add(line, piece, sizes)
    end
  end

  defp content(line, piece, at, chunk_size) do
    cond do
      piece.key != nil and item?(:map, line) ->
        next_piece(piece, line, at, %{kind: :map, pad: "", key: nil})

      piece.size - piece.doc_size >= chunk_size and item?(piece.kind, piece.pad, line) ->
        next_piece(piece, line, at, %{})

      true ->
        {[], append(line, piece)}
    end
  end

  defp next_piece(piece, line, at, changes) do
    next = Map.merge(%{piece | continued: true}, changes)
    head = Enum.reverse(["---" | piece.directives]) ++ List.wrap(next.key)

    next = %{
      next
      | lines: [],
        count: 0,
        size: 0,
        start: at - length(head),
        doc_size: 0
    }

    {[finish(piece)], Enum.reduce(head ++ [line], next, &append/2)}
  end

  defp start(line, piece, at, join_size) do
    {done, piece} =
      cond do
        not piece.begun -> {[], piece}
        piece.size >= join_size -> {document(piece), new(at)}
        true -> {[], next_document(piece)}
      end

    {done, line |> append(%{piece | in_document: true, begun: true}) |> after_marker(line)}
  end

  defp starts?(line) do
    case String.trim_leading(line) do
      "" -> false
      <<c, _::binary>> -> c not in ~c"#%"
    end
  end

  defp append(line, piece) do
    %{
      piece
      | lines: [[line, "\n"] | piece.lines],
        count: piece.count + 1,
        size: piece.size + byte_size(line) + 1
    }
  end

  defp marker?(line, marker) do
    case line do
      ^marker -> true
      <<^marker::binary-size(3), c, _::binary>> -> c in ~c" \t\r"
      _ -> false
    end
  end

  defp after_marker(piece, <<_::binary-size(3), rest::binary>>) do
    case String.trim(rest) do
      "" -> piece
      "#" <> _ -> piece
      _ -> %{piece | kind: :none}
    end
  end

  defp first_line(line, piece) do
    case String.trim(line) do
      "" ->
        piece

      "#" <> _ ->
        piece

      "%" <> _ ->
        %{piece | directives: [line | piece.directives]}

      trimmed ->
        unindented = String.trim_leading(line, " ")
        pad = binary_part(line, 0, byte_size(line) - byte_size(unindented))
        %{piece | kind: kind(unindented, trimmed), pad: pad}
    end
  end

  defp kind(line, trimmed) do
    cond do
      item?(:list, line) -> :list
      :binary.first(line) in ~c" \t[]{}\"'|>!&*?:%@`," -> :none
      String.contains?(line, ": ") or String.ends_with?(trimmed, ":") -> :map
      true -> :none
    end
  end

  defp item?(kind, pad, line) do
    size = byte_size(pad)

    case line do
      <<^pad::binary-size(^size), rest::binary>> -> item?(kind, rest)
      _ -> false
    end
  end

  defp item?(:list, "-"), do: true
  defp item?(:list, <<"-", c, _::binary>>), do: c in ~c" \t\r"
  defp item?(:map, ""), do: false

  # Only a key line starts a pair, so any other line stays with the one before and fails to parse
  defp item?(:map, line) do
    [line | _comment] = String.split(line, " #", parts: 2)

    not item?(:list, line) and :binary.first(line) not in ~c" \t\r#:]}" and
      (String.contains?(line, ": ") or String.ends_with?(String.trim_trailing(line), ":"))
  end

  defp item?(_kind, _line), do: false
end
