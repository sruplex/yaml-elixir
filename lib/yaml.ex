defmodule YAML do
  @moduledoc """
  Documentation for YAML.
  """
  alias YAML.Parser
  alias YAML.ArgumentError

  @doc """
   Decodes YAML strings into Elixir data structures or AST.
  ## Options
    * `:detailed` - controls whether to return AST with metadata or simplified data
    (default: `false`)

      * `false` (default) - returns plain Elixir maps, lists, and primitives
      * `true` - returns full AST with metadata (line numbers, column numbers, tags)

    * `:return` - selects which decoded YAML documents are returned. It may be
      one of `:auto`, `:first_document` or `:all_documents`.

        * `:auto` (default) - automatically determines the return format based on
          the input. Single-document input returns the decoded value directly
          single document (map or list), while multi-document input returns a
          list with all decoded documents.
        * `:first_document` - returns only the first decoded YAML document.
        * `:all_documents` - returns all decoded YAML documents as a list.


  ## Examples

      iex> YAML.decode("- a: 1")
      {:ok, [[%{"a" => 1}]]}

      iex> YAML.decode("a: 1", return: :first_document)
      {:ok, %{"a" => 1}}


  """

  def decode(binary, opts \\ []) when is_binary(binary) do
    with {:ok, opts} <- validate_opts(opts),
         {:ok, yaml} <- Parser.parse(binary) do
      {:ok, apply_options(yaml, opts)}
    end
  end

  def decode!(binary, opts \\ []) when is_binary(binary) do
    case decode(binary, opts) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  @default_opts [return: :auto, detailed: false]
  defp validate_opts(opts) do
    @default_opts
    |> Keyword.merge(opts)
    |> Enum.reduce_while({:ok, []}, fn
      {:return, v} = opt, {:ok, acc} when v in [:auto, :all_documents, :first_document] ->
        {:cont, {:ok, [opt | acc]}}

      {:return, v}, {:ok, _acc} ->
        error =
          ArgumentError.invalid_option(
            :return,
            v,
            "must be one of [:auto, :all_documents, :first_document]"
          )

        {:halt, {:error, error}}

      {:detailed, v} = opt, {:ok, acc} when is_boolean(v) ->
        {:cont, {:ok, [opt | acc]}}

      {:detailed, v}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(:detailed, v, "must be a boolean")
        {:halt, {:error, error}}

      {key, _val}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(key, nil, "unknown option")
        {:halt, {:error, error}}
    end)
  end

  defp apply_options(yaml, opts) do
    Enum.reduce(opts, yaml, fn
      {:return, :auto}, yaml -> yaml
      {:return, :all_documents}, yaml -> yaml
      {:return, :first_document}, [first | _] -> first
      {:detailed, true}, yaml -> yaml
      {:detailed, false}, yaml -> Parser.simplify(yaml)
    end)
  end
end
