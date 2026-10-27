# Changelog

## Unreleased

### Breaking

- `YAML.decode/2` returns a single document directly instead of a one-element list,
  and `nil` for empty input. Change `{:ok, [doc]} = YAML.decode(...)` to
  `{:ok, doc} = YAML.decode(...)`.

### Added

- `YAML.encode/2` and `YAML.encode!/2`.
- `YAML.encode_to_iodata/2` and `YAML.encode_to_iodata!/2`.
- `YAML.EncodeError`, with `:cause` and the `:location` of the value that failed.

### Fixed

- `return: :first_document` returns `nil` for empty input instead of crashing.
- Non-tuple `yamerl_opts` return an error instead of crashing.
- Unknown option errors name the option.

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
