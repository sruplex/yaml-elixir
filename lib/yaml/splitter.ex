defmodule YAML.Splitter do
  @moduledoc false

  # Cuts YAML chunks into {document, first_line}; a "---" or "..." line ends a document

  @spec split(Enumerable.t()) :: Enumerable.t({String.t(), pos_integer()})
  def split(enumerable) do
    # lines are newest first; start is the document's first line, line the next one
    start = fn -> %{rest: "", lines: [], start: 1, line: 1, in_document: false} end
    Stream.transform(enumerable, start, &split_chunk/2, &finish/1, fn _state -> :ok end)
  end

  # Only the new chunk is searched, so a long line read in many chunks stays linear
  defp split_chunk(chunk, state) do
    case :binary.split(chunk, "\n", [:global]) do
      [part] -> {[], %{state | rest: [state.rest | part]}}
      [first | parts] -> add_lines(IO.iodata_to_binary([state.rest | first]), parts, state, [])
    end
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
      marker?(line, "---") and state.in_document ->
        done = finish_document(state)

        {done,
         %{state | lines: [line], start: state.line, line: state.line + 1, in_document: true}}

      marker?(line, "...") ->
        done = finish_document(push(state, line))

        {done,
         %{state | lines: [], start: state.line + 1, line: state.line + 1, in_document: false}}

      state.in_document ->
        {[], push(state, line)}

      # Outside a document, a blank line, comment or directive doesn't start one
      match?(<<c, _::binary>> when c not in ~c"#%", String.trim_leading(line)) ->
        {[], %{push(state, line) | in_document: true}}

      true ->
        {[], push(state, line)}
    end
  end

  defp push(state, line), do: %{state | lines: [line | state.lines], line: state.line + 1}

  defp finish_document(state, ending \\ "\n")

  defp finish_document(%{in_document: false}, _ending), do: []

  defp finish_document(%{lines: [last | lines]} = state, ending) do
    text = lines |> Enum.reduce([last, ending], &[&1, ?\n | &2]) |> IO.iodata_to_binary()
    [{text, state.start}]
  end

  defp marker?(<<marker::binary-size(3)>>, marker), do: true
  defp marker?(<<marker::binary-size(3), c, _::binary>>, marker) when c in ~c" \t\r", do: true
  defp marker?(_line, _marker), do: false
end
