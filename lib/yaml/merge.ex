defmodule YAML.Merge do
  @moduledoc """
  Resolves YAML merge keys (<<) in AST documents.

  ## Example

  Input YAML:
  ```yaml
  description: "This is line one\\nThis is line two\\n"
  defaults:
    retries: 3
    timeout: 30
    created_at: "2025-01-01T00:00:00Z"
  service_a:
    <<: *defaults
    timeout: 60
  ```

  Input AST:
  ```elixir
  [
    %YAML.AST.Document{
      root: %YAML.AST.Mapping{
        pairs: [
          {%YAML.AST.Scalar{value: "description", ...},
           %YAML.AST.Scalar{value: "This is line one\\nThis is line two\\n", ...}},
          {%YAML.AST.Scalar{value: "defaults", ...},
           %YAML.AST.Mapping{
             pairs: [
               {%YAML.AST.Scalar{value: "retries", ...}, %YAML.AST.Scalar{value: 3, ...}},
               {%YAML.AST.Scalar{value: "timeout", ...}, %YAML.AST.Scalar{value: 30, ...}},
               {%YAML.AST.Scalar{value: "created_at", ...}, %YAML.AST.Scalar{value: "2025-01-01T00:00:00Z", ...}}
             ], ...
           }},
          {%YAML.AST.Scalar{value: "service_a", ...},
           %YAML.AST.Mapping{
             pairs: [
               {%YAML.AST.Scalar{value: "<<", ...}, %YAML.AST.Mapping{pairs: [...], ...}},
               {%YAML.AST.Scalar{value: "timeout", ...}, %YAML.AST.Scalar{value: 60, ...}}
             ], ...
           }}
        ], ...
      }
    }
  ]
  ```

  Output AST (after merge):
  ```elixir
  [
    %YAML.AST.Document{
      root: %YAML.AST.Mapping{
        pairs: [
          {%YAML.AST.Scalar{value: "description", ...},
           %YAML.AST.Scalar{value: "This is line one\\nThis is line two\\n", ...}},
          {%YAML.AST.Scalar{value: "defaults", ...},
           %YAML.AST.Mapping{
             pairs: [
               {%YAML.AST.Scalar{value: "retries", ...}, %YAML.AST.Scalar{value: 3, ...}},
               {%YAML.AST.Scalar{value: "timeout", ...}, %YAML.AST.Scalar{value: 30, ...}},
               {%YAML.AST.Scalar{value: "created_at", ...}, %YAML.AST.Scalar{value: "2025-01-01T00:00:00Z", ...}}
             ], ...
           }},
          {%YAML.AST.Scalar{value: "service_a", ...},
           %YAML.AST.Mapping{
             pairs: [
               # << key removed, pairs merged:
               {%YAML.AST.Scalar{value: "retries", ...}, %YAML.AST.Scalar{value: 3, ...}},
               {%YAML.AST.Scalar{value: "created_at", ...}, %YAML.AST.Scalar{value: "2025-01-01T00:00:00Z", ...}},
               {%YAML.AST.Scalar{value: "timeout", ...}, %YAML.AST.Scalar{value: 60, ...}}  # overridden value
             ], ...
           }}
        ], ...
      }
    }
  ]
  ```

  Notice:
  - The `<<` key is removed from service_a
  - `retries` and `created_at` are merged from defaults
  - `timeout` is overridden to 60 (local value wins)
  """

  alias YAML.AST.{Document, Mapping, List, Scalar}

  def apply(%Document{root: root} = doc) do
    %{doc | root: apply(root)}
  end

  def apply(documents) when is_list(documents) do
    Enum.map(documents, &apply/1)
  end

  def apply(%Mapping{pairs: pairs} = mapping) do
    pairs = Enum.map(pairs, fn {k, v} -> {apply(k), apply(v)} end)

    {merge_keys, normal_keys} =
      Enum.split_with(pairs, fn {k, _} ->
        match?(%Scalar{value: "<<"}, k)
      end)

    final_pairs =
      if merge_keys == [] do
        pairs
      else
        merged = Enum.flat_map(merge_keys, fn {_, val} -> extract_pairs(val) end)
        do_merge(merged, normal_keys)
      end

    %{mapping | pairs: final_pairs}
  end

  def apply(%List{items: items} = list) do
    %{list | items: Enum.map(items, &apply/1)}
  end

  def apply(%Scalar{} = scalar), do: scalar

  def apply(value), do: value

  defp extract_pairs(%Mapping{pairs: p}), do: p

  defp extract_pairs(%List{items: items}) do
    items
    |> Enum.reverse()
    |> Enum.flat_map(fn
      %Mapping{pairs: p} -> p
      _ -> []
    end)
  end

  defp extract_pairs(_), do: []

  defp do_merge(merged_pairs, normal_pairs) do
    (merged_pairs ++ normal_pairs)
    |> Enum.reverse()
    |> Enum.uniq_by(fn {k, _} -> get_value(k) end)
    |> Enum.reverse()
  end

  defp get_value(%Scalar{value: v}), do: v
  defp get_value(other), do: other
end
