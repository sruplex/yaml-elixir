defmodule YAML.Splitter do
  @moduledoc false

  # Cuts a stream of YAML chunks into one string per document, with the line it starts on.
  # Per the YAML spec, a "---" or "..." line can't be part of any value, so it always marks
  # a document boundary.

  @spec split(Enumerable.t()) :: Enumerable.t()
  def split(enumerable) do
    # rest: the unfinished last line, as iodata; lines: the current document, newest first;
    # start: its first line number; line: the next line number; document?: it has content
    start = fn -> %{rest: "", lines: [], start: 1, line: 1, document?: false} end
    Stream.transform(enumerable, start, &split_chunk/2, &finish/1, fn _state -> :ok end)
  end

  # Only the new chunk is searched, so a long line read in many chunks stays linear
  defp split_chunk(chunk, state) when is_binary(chunk) do
    case :binary.split(chunk, "\n", [:global]) do
      [part] -> {[], %{state | rest: [state.rest | part]}}
      [first | parts] -> add_lines(IO.iodata_to_binary([state.rest | first]), parts, state, [])
    end
  end

  defp split_chunk(chunk, _state) do
    raise ArgumentError, "expected a stream of binaries, got: #{inspect(chunk)}"
  end

  # The last line had no newline, so none is added after it
  defp finish(state) do
    case IO.iodata_to_binary(state.rest) do
      "" ->
        {finish_document(state), state}

      line ->
        {documents, state} = add_line(line, state)
        {documents ++ finish_document(state, ""), state}
    end
  end

  # The last part has no newline yet, so it is kept as the rest
  defp add_lines(line, [next | parts], state, documents) do
    {done, state} = add_line(line, state)
    add_lines(next, parts, state, done ++ documents)
  end

  defp add_lines(rest, [], state, documents), do: {Enum.reverse(documents), %{state | rest: rest}}

  defp add_line(line, state) do
    cond do
      marker?(line, "---") and state.document? ->
        done = finish_document(state)
        {done, %{state | lines: [line], start: state.line, line: state.line + 1, document?: true}}

      marker?(line, "...") ->
        done = finish_document(push(state, line))

        {done,
         %{state | lines: [], start: state.line + 1, line: state.line + 1, document?: false}}

      state.document? ->
        {[], push(state, line)}

      # Outside a document, a blank line, comment or directive doesn't start one
      match?(<<c, _::binary>> when c not in ~c"#%", String.trim_leading(line)) ->
        {[], %{push(state, line) | document?: true}}

      true ->
        {[], push(state, line)}
    end
  end

  defp push(state, line), do: %{state | lines: [line | state.lines], line: state.line + 1}

  defp finish_document(state, ending \\ "\n")

  defp finish_document(%{document?: false}, _ending), do: []

  defp finish_document(%{lines: [last | lines]} = state, ending) do
    text = lines |> Enum.reduce([last, ending], &[&1, ?\n | &2]) |> IO.iodata_to_binary()
    [{text, state.start}]
  end

  defp marker?(<<marker::binary-size(3)>>, marker), do: true
  defp marker?(<<marker::binary-size(3), c, _::binary>>, marker) when c in ~c" \t\r", do: true
  defp marker?(_line, _marker), do: false
end
