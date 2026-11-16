# Cookbook

Short recipes for common tasks.

## Load a config file into a struct

Fields missing from the file keep their default:

```elixir
defmodule MyApp.Config do
  defstruct port: 4000, host: "localhost", debug: false
end

# app.yml:
#   port: 8080
#   debug: true

YAML.decode_file!("app.yml", as: %MyApp.Config{})
#=> %MyApp.Config{port: 8080, host: "localhost", debug: true}
```

## Read front matter from Markdown

```elixir
markdown = """
---
title: Hello
tags: [elixir, yaml]
---
# Hello
"""

[_, front_matter, body] = String.split(markdown, "---\n", parts: 3)

YAML.decode!(front_matter)
#=> %{"title" => "Hello", "tags" => ["elixir", "yaml"]}

body
#=> "# Hello\n"
```

## Read a file with many documents

Files such as Kubernetes manifests hold several documents split by `---`:

```elixir
YAML.decode!("kind: Service\nname: web\n---\nkind: Deployment\nname: web\n")
#=> [%{"kind" => "Service", "name" => "web"}, %{"kind" => "Deployment", "name" => "web"}]
```

A single document is returned on its own. To always get a list, use `return: :all_documents`:

```elixir
YAML.decode!("kind: Service\n", return: :all_documents)
#=> [%{"kind" => "Service"}]
```

## Process a large file one document at a time

`YAML.decode_stream!/2` reads one document at a time, so the whole file is never in memory:

```elixir
"events.yml"
|> File.stream!()
|> YAML.decode_stream!()
|> Stream.map(& &1["id"])
|> Enum.to_list()
#=> [1, 2, 3]
```

## Write structs to YAML

Derive `YAML.Encoder`, and leave out fields that must not be written:

```elixir
defmodule MyApp.User do
  @derive {YAML.Encoder, except: [:password]}
  defstruct [:name, :email, :password]
end

YAML.encode!([%MyApp.User{name: "Ada", email: "ada@example.com", password: "secret"}])
#=> "---\n- name: Ada\n  email: ada@example.com\n"
```

To write it to a file, use `YAML.encode_file!/3`.

## Read custom tags

Give a function for each tag. It gets the tagged value and returns what to use instead:

```elixir
YAML.decode!("price: !money 12.50", tags: %{"!money" => &Decimal.new/1})
#=> %{"price" => Decimal.new("12.50")}
```

## Use atom keys safely

`atomize_keys: :safe` only uses atoms that already exist, so untrusted input can't fill the atom
table. Keys without an existing atom stay strings:

```elixir
YAML.decode!("name: Ada\nrole: admin", atomize_keys: :safe)
#=> %{:name => "Ada", "role" => "admin"}
```

## Show where a parse error is

```elixir
case YAML.decode("name: [Ada") do
  {:ok, data} ->
    data

  {:error, %YAML.ParsingError{message: message, location: {line, column}}} ->
    IO.puts("#{message} at line #{line}, column #{column}")
end
#=> while parsing a flow sequence, expected ',' or ']' at line 1, column 11
```

## Share values with anchors and merge keys

`<<` merges the keys of an anchored map:

```elixir
yaml = """
defaults: &defaults
  adapter: postgres
  pool: 5
dev:
  <<: *defaults
  database: dev_db
"""

YAML.decode!(yaml)["dev"]
#=> %{"adapter" => "postgres", "pool" => 5, "database" => "dev_db"}
```

Use `enable_merge: false` to keep `<<` as a normal key.

## Keep values like "1.10" or "01234" as strings

Plain values that look like numbers are decoded as numbers. Quote them to keep them as strings:

```elixir
YAML.decode!("version: 1.10")              #=> %{"version" => 1.1}
YAML.decode!("version: \"1.10\"")          #=> %{"version" => "1.10"}
```

`YAML.encode/2` quotes such strings for you, so they decode back the same:

```elixir
YAML.encode!(%{"version" => "1.10", "zip" => "01234"})
#=> "---\nversion: \"1.10\"\nzip: \"01234\"\n"
```

## Read YAML 1.1 files

The default `:core` schema reads `yes`, `no`, `on` and `off` as strings. Older files that mean
them as booleans need `schema: :yaml11`:

```elixir
YAML.decode!("enabled: yes")                     #=> %{"enabled" => "yes"}
YAML.decode!("enabled: yes", schema: :yaml11)    #=> %{"enabled" => true}
```
