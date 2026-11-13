# Changelog

## Unreleased

### Breaking

- Decoding uses a Rust parser instead of yamerl, and is about 10 times faster. The parser is downloaded
  prebuilt for macOS, Linux and Windows, so no Rust toolchain is needed. Set `YAML_BUILD=true` to build it from source.
- Requires Elixir `~> 1.16`, the oldest version `rustler_precompiled` supports. On Elixir 1.14 or 1.15, stay on `{:yaml, "~> 0.3.0"}`.
- The `:yamerl_opts` option is replaced by `:schema`. Change `yamerl_opts: [schema: :yaml11]` to `schema: :yaml11`.
- Parse error messages are worded differently.
- `YAML.Parser.parse/2` and `parse!/2` take a schema atom instead of yamerl options.
  Change `YAML.Parser.parse(yaml, schema: :yaml11)` to `YAML.Parser.parse(yaml, :yaml11)`.
- Input must be UTF-8. yamerl also read UTF-16 and UTF-32.

### Added

- `YAML.Encoder` protocol to encode structs, with `@derive` and its `:only` and `:except` options.
- `:as` decode option to decode into structs, and a `YAML.Decoder` protocol to decode other data into a struct.
- `YAML.decode_file/2`, `YAML.encode_file/3` and their `!` versions, to read and write YAML files.
- `:tags` decode option to turn custom tags such as `!money` into your own values.

### Fixed

- An alias to a flow map or list gives the whole node, not its first value.
- A `|+` or `>+` block at the end of the input keeps its last blank lines.
- Custom tags such as `!thing` are accepted instead of returning an error.
- Every `<<` key in a map is merged, not only the last one.
- Aliases that would add over a million values, and over ten times the values written out, return an error,
  so a small file can't expand into gigabytes of memory.
- Invalid UTF-8 returns an error with the line and column of the first bad byte.

## v0.3.0 (2026-11-09)

### Breaking

- `YAML.decode/2` returns a single document directly instead of a one-element list,
  and `nil` for empty input. Change `{:ok, [doc]} = YAML.decode(...)` to
  `{:ok, doc} = YAML.decode(...)`.

### Added

- `YAML.encode/2` and `YAML.encode!/2`, for Elixir data, a `YAML.AST.Document` or a list of them (#18).
- `YAML.encode_to_iodata/2` and `YAML.encode_to_iodata!/2` (#18).
- `YAML.encode_stream/2` and `YAML.encode_stream!/2` (#19).
- `YAML.decode_stream/2` and `YAML.decode_stream!/2` (#19).
- `:sort_maps` encode option to write map keys in sorted order (#18).
- `YAML.EncodeError`, with `:type` and the `:location` of the value that failed (#9).

### Fixed

- `return: :first_document` returns `nil` for empty input instead of crashing.
- Non-tuple `yamerl_opts` return an error instead of crashing.
- Unknown option errors name the option.
- Hex package and documentation links point to the right GitHub repository.
- Input that crashes yamerl's parser returns an error instead of raising.

## v0.2.0 (2026-08-30)

### Breaking

- `YAML.decode/2` returns a list of documents, even for a single document.
- Requires Elixir `~> 1.14` and yamerl `~> 0.10`.

### Added

- `:return` option to select `:auto`, `:first_document` or `:all_documents` (#2).
- `:detailed` option to return the YAML AST with line, column and tag metadata (#3).
- Merge keys (`<<`) with the `:enable_merge` option (#4).
- `YAML.ArgumentError` for invalid options (#4).
- `:atomize_keys` and `:yamerl_opts` options (#5).

## v0.1.0 (2018-12-24)

- `YAML.decode/1` and `YAML.decode!/1`, a wrapper around yamerl.
- `YAML.ParsingError` for invalid YAML.
