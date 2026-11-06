defmodule YAML.Splitter do
  @moduledoc false

  # Cuts a stream of YAML chunks into one string per document, with the line it starts on.
  # A "---" or "..." line can't be part of any value, so it always marks a document boundary.

  @spec split(Enumerable.t()) :: Enumerable.t()
  def split(enumerable) do
    Stream.transform(enumerable, &new_state/0, &split_chunk/2, &finish/1, fn _state -> :ok end)
  end

  # rest: the unfinished last line, as iodata; lines: the current document, newest first;
  # start: its first line number; line: the next line number; document?: it has content
  defp new_state, do: %{rest: "", lines: [], start: 1, line: 1, document?: false}

  # Only the new chunk is searched, so a long line read in many chunks stays linear
  defp split_chunk(chunk, state) do
    case :binary.split(chunk, "\n", [:global]) do
      [part] ->
        {[], %{state | rest: [state.rest | part]}}

      [first | parts] ->
        [rest | lines] = Enum.reverse(parts)
        line = IO.iodata_to_binary([state.rest | first])
        add_lines([line | Enum.reverse(lines)], %{state | rest: rest}, [])
    end
  end

  defp finish(state) do
    case IO.iodata_to_binary(state.rest) do
      "" ->
        {finish_document(state), state}

      line ->
        {documents, state} = add_lines([line], %{state | rest: ""}, [])
        {documents ++ finish_document(state), state}
    end
  end

  defp add_lines([line | rest], state, documents) do
    {done, state} = add_line(line, state)
    add_lines(rest, state, done ++ documents)
  end

  defp add_lines([], state, documents), do: {Enum.reverse(documents), state}

  defp add_line(line, state) do
    cond do
      marker?(line, "---") and state.document? ->
        done = finish_document(state)
        {done, %{state | lines: [line], start: state.line, line: state.line + 1, document?: true}}

      marker?(line, "...") ->
        done = finish_document(push(state, line))

        {done,
         %{state | lines: [], start: state.line + 1, line: state.line + 1, document?: false}}

      state.document? or not content?(line) ->
        {[], push(state, line)}

      true ->
        {[], %{push(state, line) | document?: true}}
    end
  end

  defp push(state, line), do: %{state | lines: [line | state.lines], line: state.line + 1}

  defp finish_document(%{document?: false}), do: []

  defp finish_document(state) do
    text = state.lines |> Enum.reduce([], &[&1, ?\n | &2]) |> IO.iodata_to_binary()
    [{text, state.start}]
  end

  defp marker?(<<marker::binary-size(3)>>, marker), do: true
  defp marker?(<<marker::binary-size(3), c, _::binary>>, marker) when c in ~c" \t\r", do: true
  defp marker?(_line, _marker), do: false

  # Outside a document, blank lines, comments and directives don't start one
  defp content?(line) do
    case String.trim_leading(line) do
      "" -> false
      "#" <> _ -> false
      "%" <> _ -> false
      _ -> true
    end
  end
end
