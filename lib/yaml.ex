defmodule YAML do
  @moduledoc """
  Documentation for YAML.
  """
  alias YAML.Parser
  alias YAML.Merge
  alias YAML.Encode
  alias YAML.ArgumentError
  alias YAML.EncodeError
  alias YAML.AST.Document

  @valid_yamerl_opts [
    :schema,
    :node_mods,
    :keep_duplicate_keys
  ]

  @valid_schema_values [:failsafe, :json, :core, :yaml11]
  @valid_map_node_format_values [:map, :proplist]

  @doc """
   Decodes YAML strings into Elixir data structures or AST.
  ## Options
    * `:detailed` - controls whether to return AST with metadata or simplified data
    (default: `false`)

      * `false` (default) - returns plain Elixir maps, lists, and primitives
      * `true` - returns full AST with metadata (line numbers, column numbers, tags)

    * `:return` - selects which decoded YAML documents are returned. It may be
      one of `:auto`, `:first_document` or `:all_documents`.

        * `:auto` (default) - returns the document itself for single-document
          input, a list for multi-document input, or `nil` for empty input.
        * `:first_document` - returns only the first decoded YAML document, or
          `nil` if the input is empty.
        * `:all_documents` - returns all decoded YAML documents as a list.

    * `:enable_merge` - controls YAML merge key behavior (default: `true`)

        * `true` (default) - processes `<<` as merge keys (YAML 1.1 behavior)
        * `false` - treats `<<` as regular keys (YAML 1.2+ behavior)

    * `:atomize_keys` - controls whether map keys are converted to atoms (default: `false`)

        * `false` (default) - keeps all keys as binary strings
        * `:safe` - converts keys to atoms only if the atom already exists in the atom table
        * `true` - converts all keys to atoms (only use for trusted input)

    * `:yamerl_opts` - list of additional options passed directly to `:yamerl_constr`
      (default: `[]`). Note: `:str_node_as_binary` and `:detailed_constr` are always
      set internally and should not be passed here.

        * `{:schema, :failsafe | :json | :core | :yaml11}` - YAML schema for type resolution (default: `:core`)
        * `{:node_mods, [module()]}` - extra modules for custom node types (default: `[]`)
        * `{:keep_duplicate_keys, boolean()}` - preserve duplicate map keys (default: `false`)

  ## Examples

      iex> YAML.decode("- a: 1")
      {:ok, [%{"a" => 1}]}

      iex> YAML.decode("a: 1\\n---\\nb: 2")
      {:ok, [%{"a" => 1}, %{"b" => 2}]}

      iex> YAML.decode("a: 1", return: :first_document)
      {:ok, %{"a" => 1}}

      iex> YAML.decode("a: 1", yamerl_opts: [{:schema, :core}, {:map_node_format, :map}])
      {:ok, %{"a" => 1}}

  """

  def decode(binary, opts \\ []) when is_binary(binary) do
    with {:ok, opts} <- validate_opts(opts),
         yamerl_opts = Keyword.get(opts, :yamerl_opts, []),
         {:ok, yaml} <- Parser.parse(binary, yamerl_opts) do
      {:ok, apply_options(yaml, opts)}
    end
  end

  def decode!(binary, opts \\ []) when is_binary(binary) do
    case decode(binary, opts) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  @doc """
  Encodes Elixir data, a YAML AST document or a list of documents into YAML.

  ## Options

    * `:sort_maps` - writes map keys in sorted order instead of the map's own order (default: `false`)

  ## Types

    * Atoms are written as strings, except `nil`, `true`, `false`, `:nan`, `:"+inf"` and `:"-inf"`
    * `:nan`, `:"+inf"` and `:"-inf"` are written as `.nan`, `.inf` and `-.inf`
    * Dates and times are written as quoted ISO 8601 strings
    * Other structs return an error
    * An atom key and a string key with the same text return an error
    * Without `:sort_maps`, map keys follow Elixir's map order, which isn't alphabetical for atom keys

  ## Examples

      iex> YAML.encode(%{"a" => 1})
      {:ok, "---\\na: 1\\n"}

      iex> YAML.encode(%{c: 1, a: 2}, sort_maps: true)
      {:ok, "---\\na: 2\\nc: 1\\n"}

      iex> {:error, error} = YAML.encode({1, 2})
      iex> error.message
      "cannot encode tuple"

  """
  @spec encode(term(), keyword()) ::
          {:ok, binary()} | {:error, EncodeError.t() | ArgumentError.t()}
  def encode(term, opts \\ []) when is_list(opts) do
    with {:ok, iodata} <- encode_to_iodata(term, opts) do
      {:ok, IO.iodata_to_binary(iodata)}
    end
  end

  @doc """
  Same as `encode/2`, but raises on error.

  ## Examples

      iex> YAML.encode!([1, 2])
      "---\\n- 1\\n- 2\\n"

  """
  @spec encode!(term(), keyword()) :: binary()
  def encode!(term, opts \\ []) when is_list(opts) do
    case encode(term, opts) do
      {:ok, yaml} -> yaml
      {:error, error} -> raise error
    end
  end

  @doc """
  Same as `encode/2`, but returns iodata, which is faster to write to a file or socket.

  ## Examples

      iex> {:ok, iodata} = YAML.encode_to_iodata(%{"a" => 1})
      iex> IO.iodata_to_binary(iodata)
      "---\\na: 1\\n"

  """
  @spec encode_to_iodata(term(), keyword()) ::
          {:ok, iodata()} | {:error, EncodeError.t() | ArgumentError.t()}
  def encode_to_iodata(term, opts \\ []) when is_list(opts) do
    with {:ok, sort} <- validate_encode_opts(opts, false) do
      # A list starting with a document is written as one document each
      case term do
        %Document{} ->
          Encode.document(term)

        [%Document{} | _] ->
          Encode.documents(term)

        _ ->
          Encode.data(term, sort)
      end
    end
  end

  @doc """
  Same as `encode_to_iodata/2`, but raises on error.

  ## Examples

      File.write!("config.yml", YAML.encode_to_iodata!(data))

  """
  @spec encode_to_iodata!(term(), keyword()) :: iodata()
  def encode_to_iodata!(term, opts \\ []) when is_list(opts) do
    case encode_to_iodata(term, opts) do
      {:ok, iodata} -> iodata
      {:error, error} -> raise error
    end
  end

  @doc """
  Lazily encodes each item of an enumerable as one YAML document, yielding
  `{:ok, iodata}` or `{:error, error}` for each. Raises `YAML.ArgumentError` on invalid options.

  ## Examples

      iex> [%{"a" => 1}, {1, 2}] |> YAML.encode_stream() |> Enum.map(&elem(&1, 0))
      [:ok, :error]

  """
  @spec encode_stream(Enumerable.t(), keyword()) ::
          Enumerable.t({:ok, iodata()} | {:error, EncodeError.t()})
  def encode_stream(enumerable, opts \\ []) when is_list(opts) do
    sort =
      case validate_encode_opts(opts, false) do
        {:ok, sort} -> sort
        {:error, error} -> raise error
      end

    enumerable
    |> Stream.with_index()
    |> Stream.map(fn {item, index} ->
      written =
        if match?(%Document{}, item), do: Encode.document(item), else: Encode.data(item, sort)

      # Adds the item's index to the location of its error
      with {:error, error} <- written, do: {:error, EncodeError.prepend_location(error, index)}
    end)
  end

  @doc """
  Same as `encode_stream/2`, but yields iodata and raises on error.

  ## Examples

      iex> stream = YAML.encode_stream!([%{"a" => 1}, [1, 2]])
      iex> stream |> Enum.to_list() |> IO.iodata_to_binary()
      "---\\na: 1\\n---\\n- 1\\n- 2\\n"

  To write a file:

      data
      |> YAML.encode_stream!()
      |> Stream.into(File.stream!("out.yml", [:delayed_write]))
      |> Stream.run()

  """
  @spec encode_stream!(Enumerable.t(), keyword()) :: Enumerable.t(iodata())
  def encode_stream!(enumerable, opts \\ []) when is_list(opts) do
    enumerable
    |> encode_stream(opts)
    |> Stream.map(fn
      {:ok, iodata} -> iodata
      {:error, error} -> raise error
    end)
  end

  # Returns the :sort_maps value, the only encode option
  defp validate_encode_opts([], sort), do: {:ok, sort}

  defp validate_encode_opts([{:sort_maps, v} | rest], _sort) when is_boolean(v),
    do: validate_encode_opts(rest, v)

  defp validate_encode_opts([{:sort_maps, v} | _], _sort),
    do: {:error, ArgumentError.invalid_option(:sort_maps, v, "must be a boolean")}

  defp validate_encode_opts([{key, value} | _], _sort) when is_atom(key),
    do: {:error, ArgumentError.invalid_option(key, value, "unknown option #{inspect(key)}")}

  defp validate_encode_opts([opt | _], _sort),
    do: {:error, ArgumentError.invalid_option(nil, opt, "expected a keyword list")}

  @default_opts [
    return: :auto,
    detailed: false,
    enable_merge: true,
    atomize_keys: false,
    yamerl_opts: []
  ]

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

      {:enable_merge, v} = opt, {:ok, acc} when is_boolean(v) ->
        {:cont, {:ok, [opt | acc]}}

      {:enable_merge, v}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(:enable_merge, v, "must be a boolean")
        {:halt, {:error, error}}

      {:atomize_keys, v} = opt, {:ok, acc} when is_boolean(v) or v == :safe ->
        {:cont, {:ok, [opt | acc]}}

      {:atomize_keys, v}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(:atomize_keys, v, "must be a boolean or :safe")
        {:halt, {:error, error}}

      {:yamerl_opts, v}, {:ok, acc} when is_list(v) ->
        case validate_yamerl_opts(v) do
          :ok -> {:cont, {:ok, [{:yamerl_opts, v} | acc]}}
          {:error, _} = error -> {:halt, error}
        end

      {:yamerl_opts, v}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(:yamerl_opts, v, "must be a list")
        {:halt, {:error, error}}

      {key, val}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(key, val, "unknown option #{inspect(key)}")
        {:halt, {:error, error}}
    end)
  end

  defp validate_yamerl_opts(yamerl_opts) do
    Enum.reduce_while(yamerl_opts, :ok, fn
      {:schema, v}, :ok when v in @valid_schema_values ->
        {:cont, :ok}

      {:schema, v}, :ok ->
        error =
          ArgumentError.invalid_option(
            :schema,
            v,
            "must be one of #{inspect(@valid_schema_values)}"
          )

        {:halt, {:error, error}}

      {:node_mods, v}, :ok when is_list(v) ->
        {:cont, :ok}

      {:node_mods, v}, :ok ->
        error = ArgumentError.invalid_option(:node_mods, v, "must be a list of modules")
        {:halt, {:error, error}}

      {:map_node_format, v}, :ok when v in @valid_map_node_format_values ->
        {:cont, :ok}

      {:keep_duplicate_keys, v}, :ok when is_boolean(v) ->
        {:cont, :ok}

      {:keep_duplicate_keys, v}, :ok ->
        error = ArgumentError.invalid_option(:keep_duplicate_keys, v, "must be a boolean")
        {:halt, {:error, error}}

      {key, _}, :ok ->
        error =
          ArgumentError.invalid_option(
            key,
            nil,
            "unknown yamerl option. Must be one of #{inspect(@valid_yamerl_opts)}"
          )

        {:halt, {:error, error}}

      opt, :ok ->
        error =
          ArgumentError.invalid_option(
            opt,
            nil,
            "invalid yamerl option, expected a {key, value} tuple"
          )

        {:halt, {:error, error}}
    end)
  end

  @option_priority %{
    enable_merge: 1,
    detailed: 2,
    return: 3
  }

  defp apply_options(yaml, opts) do
    opts
    |> Enum.sort_by(fn {key, _} -> Map.get(@option_priority, key, 999) end)
    |> Enum.reduce(yaml, fn
      {:return, :auto}, [] -> nil
      {:return, :auto}, [single] -> single
      {:return, :auto}, yaml -> yaml
      {:return, :all_documents}, yaml -> yaml
      {:return, :first_document}, [] -> nil
      {:return, :first_document}, [first | _] -> first
      {:detailed, true}, yaml -> yaml
      {:detailed, false}, yaml -> Parser.simplify(yaml, opts[:atomize_keys])
      {:enable_merge, true}, yaml -> Merge.apply(yaml)
      {:enable_merge, false}, yaml -> yaml
      {:atomize_keys, _}, yaml -> yaml
      {:yamerl_opts, _}, yaml -> yaml
    end)
  end
end
