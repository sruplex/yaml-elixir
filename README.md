YAML
====

> YAML Encoding and Decoding in Elixir

This library is a lightweight wrapper around the erlang [`yamerl`][yamerl] package
and provides a clean and intuitive way to encode and decode YAML in Elixir.



## Installation

Add `yaml` to your project dependencies in `mix.exs`:

```elixir
def deps do
  [{:yaml, "~> 0.3.0"}]
end
```



## Usage

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



## Roadmap

 - [x] Decoder
     - [x] Multiple docs
 - [ ] Encoder
 - [ ] Streaming
 - [x] Tests
 - [x] CI

 [yamerl]: https://github.com/yakaz/yamerl/
