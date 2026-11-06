defmodule YAML.MergeKey do
  @moduledoc false

  # yamerl node module that tags a plain or !!merge << as a merge key; quoted ones stay strings

  @tag ~c"tag:yaml.org,2002:merge"

  def tags, do: [@tag]

  def try_construct_token(
        constr,
        node,
        {:yamerl_scalar, _, _, {:yamerl_tag, _, _, {:non_specific, ~c"?"}}, _, :plain, ~c"<<"} =
          token
      ),
      do: construct_token(constr, node, token)

  def try_construct_token(_constr, _node, _token), do: :unrecognized

  def construct_token(_constr, :undefined, {:yamerl_scalar, _, _, _, _, _, text} = token) do
    pres = :yamerl_constr.get_pres_details(token)
    {:finished, {:yamerl_str, __MODULE__, @tag, pres, List.to_string(text)}}
  end

  def node_pres(node), do: elem(node, 3)
end
