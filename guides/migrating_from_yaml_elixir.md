# Migrating from YamlElixir

This guide maps [YamlElixir](https://hex.pm/packages/yaml_elixir) calls to `YAML`, and lists the
differences to check when switching.

## Functions

| YamlElixir | YAML |
| --- | --- |
| `YamlElixir.read_from_string(text)` | `YAML.decode(text)` |
| `YamlElixir.read_from_string!(text)` | `YAML.decode!(text)` |
| `YamlElixir.read_all_from_string(text)` | `YAML.decode(text, return: :all_documents)` |
| `YamlElixir.read_from_file(path)` | `YAML.decode_file(path)` |
| `YamlElixir.read_all_from_file(path)` | `YAML.decode_file(path, return: :all_documents)` |
| `~y"..."` | `YAML.decode!("...")` |

YAML can also write YAML, with `YAML.encode/2` and `YAML.encode_file/3`.

## Options

| YamlElixir | YAML |
| --- | --- |
| `atoms: true` | `atomize_keys: :safe` or `atomize_keys: true` (see below) |
| `merge_anchors: true` | on by default, turn off with `enable_merge: false` |
| `maps_as_keywords: true` | not supported |
| yamerl options, such as `schema: :yaml11` | `schema: :yaml11` |

`atoms: true` only turns keys written as `:name:` into atoms. `atomize_keys` turns every key into
an atom, so write keys as `name:`:

```elixir
YamlElixir.read_from_string(":name: Ada", atoms: true)
#=> {:ok, %{name: "Ada"}}

YAML.decode("name: Ada", atomize_keys: :safe)
#=> {:ok, %{name: "Ada"}}
```

`:safe` only uses atoms that already exist, so input can't fill the atom table. Use `true` only
for trusted input.

## Differences

**Empty input** returns `nil` instead of `%{}`:

```elixir
YamlElixir.read_from_string("")   #=> {:ok, %{}}
YAML.decode("")                   #=> {:ok, nil}
```

**More than one document:** `read_from_string` returns the last document, and `YAML.decode` returns
a list of all of them. Use `return: :first_document` for only the first:

```elixir
YamlElixir.read_from_string("a: 1\n---\nb: 2")   #=> {:ok, %{"b" => 2}}
YAML.decode("a: 1\n---\nb: 2")                   #=> {:ok, [%{"a" => 1}, %{"b" => 2}]}
```

**Duplicate keys** keep the last value instead of the first:

```elixir
YamlElixir.read_from_string("a: 1\na: 2")   #=> {:ok, %{"a" => 1}}
YAML.decode("a: 1\na: 2")                   #=> {:ok, %{"a" => 2}}
```

**Merge keys** (`<<: *defaults`) are merged by default. YamlElixir keeps them as `"<<1"` keys
unless `merge_anchors: true` is given.

**Errors** are `YAML.ParsingError`, with the line and column in `:location`. A missing file returns
a `File.Error` instead of `YamlElixir.FileNotFoundError`:

```elixir
YAML.decode("a: [1")
#=> {:error, %YAML.ParsingError{location: {1, 6}, message: "while parsing a flow sequence, ..."}}

YAML.decode_file("missing.yml")
#=> {:error, %File.Error{reason: :enoent, path: "missing.yml", action: "read file"}}
```

**No yamerl:** YAML uses a Rust parser that is downloaded prebuilt, so there is no `:yamerl`
application to start and no Rust toolchain to install.
