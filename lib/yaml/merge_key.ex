defmodule YAML.MergeKey do
  @moduledoc false

  # yamerl node module that tags a plain or !!merge << as a merge key; quoted ones stay strings

  require Record

  @tokens "yamerl/include/yamerl_tokens.hrl"
  Record.defrecordp(:yamerl_scalar, Record.extract(:yamerl_scalar, from_lib: @tokens))
  Record.defrecordp(:yamerl_tag, Record.extract(:yamerl_tag, from_lib: @tokens))

  Record.defrecordp(
    :yamerl_collection_start,
    Record.extract(:yamerl_collection_start, from_lib: @tokens)
  )

  Record.defrecordp(
    :yamerl_parsing_error,
    Record.extract(:yamerl_parsing_error, from_lib: "yamerl/include/yamerl_errors.hrl")
  )

  @tag ~c"tag:yaml.org,2002:merge"

  def tags, do: [@tag]

  def try_construct_token(
        constr,
        node,
        yamerl_scalar(
          tag: yamerl_tag(uri: {:non_specific, ~c"?"}),
          substyle: :plain,
          text: ~c"<<"
        ) =
          token
      ),
      do: construct_token(constr, node, token)

  def try_construct_token(_constr, _node, _token), do: :unrecognized

  def construct_token(_constr, :undefined, yamerl_scalar(text: ~c"<<") = token) do
    pres = :yamerl_constr.get_pres_details(token)
    {:finished, {:yamerl_str, __MODULE__, @tag, pres, "<<"}}
  end

  def construct_token(_constr, :undefined, yamerl_scalar(tag: tag)), do: unrecognized(tag)

  def construct_token(_constr, :undefined, yamerl_collection_start(tag: tag)),
    do: unrecognized(tag)

  def node_pres(node), do: elem(node, 3)

  # Same error yamerl gives for an unknown tag
  defp unrecognized(yamerl_tag(line: line, column: column) = tag) do
    :yamerl_errors.throw(
      yamerl_parsing_error(
        name: :unrecognized_node,
        token: tag,
        line: line,
        column: column,
        text: ~c"Tag \"tag:yaml.org,2002:merge\" unrecognized by any module"
      )
    )
  end
end
