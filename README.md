YAML
====

> YAML Encoding and Decoding in Elixir

This library decodes YAML with a fast Rust parser and provides a clean and intuitive
way to encode and decode YAML in Elixir.



## Installation

Add `yaml` to your project dependencies in `mix.exs`:

```elixir
def deps do
  [{:yaml, "~> 0.3.0"}]
end
```

The Rust parser is downloaded prebuilt for your platform. To build it from source instead,
install Rust, set `YAML_BUILD=true` and add `{:rustler, "~> 0.38.0", runtime: false}` to your deps.



## Usage

### Decoding

To decode YAML, call the `YAML.decode/1` method:

```elixir
string = """
invoice: 34843
date   : 2001-01-23
bill-to: &id001
    given  : Chris
    family : Dumars
    address:
        lines: |
            458 Walkman Dr.
            Suite #292
        city    : Royal Oak
        state   : MI
        postal  : 48046
ship-to: *id001
product:
    - sku         : BL394D
      quantity    : 4
      description : Basketball
      price       : 450.00
    - sku         : BL4438H
      quantity    : 1
      description : Super Hoop
      price       : 2392.00
tax  : 251.42
total: 4443.52
comments: >
    Late afternoon is best.
    Backup contact is Nancy
    Billsmer @ 338-4338.
"""

YAML.decode(string)
# {:ok,
#  %{
#    "bill-to" => %{
#      "address" => %{
#        "city" => "Royal Oak",
#        "lines" => "458 Walkman Dr.\nSuite #292\n",
#        "postal" => 48046,
#        "state" => "MI"
#      },
#      "family" => "Dumars",
#      "given" => "Chris"
#    },
#    "comments" => "Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338.\n",
#    "date" => "2001-01-23",
#    "invoice" => 34843,
#    "product" => [
#      %{
#        "description" => "Basketball",
#        "price" => 450.0,
#        "quantity" => 4,
#        "sku" => "BL394D"
#      },
#      %{
#        "description" => "Super Hoop",
#        "price" => 2392.0,
#        "quantity" => 1,
#        "sku" => "BL4438H"
#      }
#    ],
#    "ship-to" => %{
#      "address" => %{
#        "city" => "Royal Oak",
#        "lines" => "458 Walkman Dr.\nSuite #292\n",
#        "postal" => 48046,
#        "state" => "MI"
#      },
#      "family" => "Dumars",
#      "given" => "Chris"
#    },
#    "tax" => 251.42,
#    "total" => 4443.52
# }}
```

### Encoding

To encode Elixir data, call the `YAML.encode/2` method:

```elixir
data = %{
  "invoice" => 34843,
  "date" => "2001-01-23",
  "bill-to" => %{
    "given" => "Chris",
    "family" => "Dumars",
    "address" => %{
      "lines" => "458 Walkman Dr.\nSuite #292\n",
      "city" => "Royal Oak",
      "state" => "MI",
      "postal" => 48046
    }
  },
  "product" => [
    %{"sku" => "BL394D", "quantity" => 4, "description" => "Basketball", "price" => 450.0},
    %{"sku" => "BL4438H", "quantity" => 1, "description" => "Super Hoop", "price" => 2392.0}
  ],
  "tax" => 251.42,
  "total" => 4443.52,
  "comments" => "Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338.\n"
}

{:ok, yaml} = YAML.encode(data)
IO.puts(yaml)
```

```yaml
---
bill-to:
  address:
    city: Royal Oak
    lines: |
      458 Walkman Dr.
      Suite #292
    postal: 48046
    state: MI
  family: Dumars
  given: Chris
comments: "Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338.\n"
date: "2001-01-23"
invoice: 34843
product:
  - description: Basketball
    price: 450.0
    quantity: 4
    sku: BL394D
  - description: Super Hoop
    price: 2392.0
    quantity: 1
    sku: BL4438H
tax: 251.42
total: 4443.52
```

To encode your own structs, derive or implement `YAML.Encoder`:

```elixir
defmodule User do
  @derive {YAML.Encoder, only: [:name, :email]}
  defstruct [:name, :email, :password]
end

YAML.encode(%User{name: "Ada", email: "ada@example.com", password: "secret"})
# {:ok, "---\nname: Ada\nemail: ada@example.com\n"}
```

To decode into your own structs, use the `:as` option:

```elixir
YAML.decode("name: Ada\nemail: ada@example.com", as: %User{})
# {:ok, %User{name: "Ada", email: "ada@example.com", password: nil}}
```

To decode custom tags such as `!money`, pass a function for each tag:

```elixir
YAML.decode("price: !money 12.50", tags: %{"!money" => &Decimal.new/1})
# {:ok, %{"price" => Decimal.new("12.50")}}
```

### Files

To read or write a whole file, use `YAML.decode_file/2` and `YAML.encode_file/3`:

```elixir
{:ok, config} = YAML.decode_file("config.yml")
:ok = YAML.encode_file(config, "copy.yml")
```

### Streaming

To read or write large files one document at a time, use
`YAML.decode_stream/2` and `YAML.encode_stream/2`:

```elixir
File.stream!("in.yml")
|> YAML.decode_stream!()
|> YAML.encode_stream!()
|> Stream.into(File.stream!("out.yml"))
|> Stream.run()
```

### Performance

Inputs over 2 KB are parsed half a millisecond at a time, so a large file doesn't hold up other
processes, and many files can be decoded at once.



## Roadmap

 - [x] Decoder
     - [x] Multiple docs
 - [x] Encoder
 - [x] Streaming
 - [x] Tests
 - [x] CI
