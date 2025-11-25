defmodule YAML do
  @moduledoc """
  Documentation for YAML.
  """

  @doc """
  Decodes a YAML string and returns Elixir data structures.

  ## Options
    * `:return` - selects which decoded YAML documents are returned. It may be
      one of `:first_document` or `:all_documents`. It also accepts the default
      behaviour when no option is given. When the default behaviour is used,
      single-document input returns the decoded value directly (map or list),
      while multi-document input returns a list with all decoded documents.

        * `:first_document` - returns only the first decoded YAML document.
        * `:all_documents` - returns all decoded YAML documents as a list.


  ## Examples

      iex> YAML.decode("- a: 1")
      {:ok, [%{"a" => 1}]}

      iex> YAML.decode("a: 1", return: :first_document)
      {:ok, %{"a" => 1}}


  """

  def decode(binary, opts \\ []) do
    {:ok, binary |> YAML.Parser.parse!() |> apply_options(opts)}
  catch
    {:yamerl_exception, error} -> YAML.ParsingError.build_tuple(error)
  end

  def decode!(binary, opts \\ []) do
    binary |> YAML.Parser.parse!() |> apply_options(opts)
  catch
    {:yamerl_exception, error} ->
      error = YAML.ParsingError.build_error(error)
      reraise(error, __STACKTRACE__)
  end

  defp apply_options(docs, opts) do
    case Keyword.get(opts, :return) do
      :first_document ->
        List.first(docs)

      :all_documents ->
        docs

      _ ->
        default_return(docs)
    end
  end

  defp default_return([single]), do: single
  defp default_return(many) when is_list(many), do: many
end
