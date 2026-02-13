defmodule YAML do
  @moduledoc """
  Documentation for YAML.
  """
  alias YAML.Parser
  alias YAML.Merge
  alias YAML.ArgumentError

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

        * `:auto` (default) - automatically determines the return format based on
          the input. Single-document input returns the decoded value directly
          single document (map or list), while multi-document input returns a
          list with all decoded documents.
        * `:first_document` - returns only the first decoded YAML document.
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
      {:ok, [[%{"a" => 1}]]}

      iex> YAML.decode("a: 1", return: :first_document)
      {:ok, %{"a" => 1}}

      iex> YAML.decode("a: 1", yamerl_opts: [{:schema, :core}, {:map_node_format, :map}])
      {:ok, [%{"a" => 1}]}

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

      {key, _val}, {:ok, _acc} ->
        error = ArgumentError.invalid_option(key, nil, "unknown option")
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
      {:return, :auto}, yaml -> yaml
      {:return, :all_documents}, yaml -> yaml
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
