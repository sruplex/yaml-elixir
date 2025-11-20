defmodule YAML do
  @moduledoc """
  Documentation for YAML.
  """

  @doc """
  Decodes a YAML string and returns Elixir data structures.

  ## Options
    * `return: :first_document` — returns only the first document.
    * `return: :all_documents` — returns all documents wrapped in a list.
    * Default — returns:
        - Single document → raw decoded value (map or list)
        - Multi-document → list of all decoded documents

  ## Examples

      iex> YAML.decode("- a: 1")
      {:ok, [%{"a" => 1}]}

      iex> YAML.decode("a: 1", return: :first_document)
      {:ok, %{"a" => 1}}

      iex> YAML.decode("a: 1\n---\nb: 2", return: :all_documents)
      {:ok, [%{"a" => 1}, %{"b" => 2}]}
  """

  def decode(binary) do
    {:ok, YAML.Parser.parse!(binary)}
  catch
    {:yamerl_exception, error} -> YAML.ParsingError.build_tuple(error)
  end

  def decode!(binary) do
    YAML.Parser.parse!(binary)
  catch
    {:yamerl_exception, error} ->
      error = YAML.ParsingError.build_error(error)
      reraise(error, __STACKTRACE__)
  end
end
