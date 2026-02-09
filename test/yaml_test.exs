defmodule YAMLTest do
  use ExUnit.Case
  doctest YAML

  alias YAML.Support.Fixtures

  describe "decode/2" do
    setup do
      yaml = Fixtures.read!(:multi_document_mixed_types)
      merge_yaml = Fixtures.read!(:merge_example)
      {:ok, yaml: yaml, merge_yaml: merge_yaml}
    end

    test "no options apply default options", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml)
      assert {:ok, ^result} = YAML.decode(yaml, return: :auto, detailed: false)
    end

    test "return: :first_document always returns the first document", %{yaml: yaml} do
      assert {:ok, doc1} = YAML.decode(yaml, return: :first_document)

      assert doc1 == %{
               "active" => true,
               "address" => %{"city" => "Lahore", "zip" => 54000},
               "age" => 25,
               "binary_data" => "Hello WORLD",
               "created_at" => "2025-01-01T12:30:45Z",
               "created_date" => "2025-01-01",
               "disabled" => false,
               "empty_field" => nil,
               "ipv4" => "192.168.1.10",
               "ipv6" => "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
               "middle_name" => nil,
               "name" => "Rizu",
               "price" => 99.99,
               "skills" => ["Elixir", "JavaScript", "Docker"]
             }
    end

    test "return: :all_documents always returns the list of all documents", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml, return: :all_documents)
      assert [doc1, doc2, doc3, doc4] = result

      assert doc1 == %{
               "active" => true,
               "address" => %{"city" => "Lahore", "zip" => 54000},
               "age" => 25,
               "binary_data" => "Hello WORLD",
               "created_at" => "2025-01-01T12:30:45Z",
               "created_date" => "2025-01-01",
               "disabled" => false,
               "empty_field" => nil,
               "ipv4" => "192.168.1.10",
               "ipv6" => "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
               "middle_name" => nil,
               "name" => "Rizu",
               "price" => 99.99,
               "skills" => ["Elixir", "JavaScript", "Docker"]
             }

      assert doc2 == %{
               "project" => %{
                 "meta" => %{
                   "build_time" => "2025-01-10T14:22:00Z",
                   "published" => false,
                   "version" => 1.0
                 },
                 "name" => "YAML Demo",
                 "tags" => ["config", "example"]
               },
               "users" => [
                 %{
                   "active" => true,
                   "id" => 1,
                   "ip" => "10.0.0.5",
                   "last_login" => "2025-01-05T08:00:00Z",
                   "name" => "Ali"
                 },
                 %{
                   "active" => false,
                   "email" => nil,
                   "id" => 2,
                   "ip" => "10.0.0.8",
                   "last_login" => nil,
                   "name" => "Sara"
                 }
               ]
             }

      assert doc3 == %{
               "defaults" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30
               },
               "description" => "This is line one\nThis is line two\n",
               "misc" => %{
                 "infinity" => :"+inf",
                 "no_value" => "no",
                 "not_a_number" => :nan,
                 "yes_value" => "yes"
               },
               "service_a" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.1",
                 "url" => "https://api.service-a.com"
               },
               "service_b" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.2",
                 "url" => "https://api.service-b.com"
               },
               "Mark McGwire" => %{"avg" => 0.278, "hr" => 65},
               "Sammy Sosa" => %{"avg" => 0.288, "hr" => 63},
               "control" => "\b1998\t1999\t2000\n",
               "hex esc" => "\r\n is \r\n",
               "quoted" => " # Not a 'comment'.",
               "single" => "\"Howdy!\" he cried.",
               "tie-fighter" => "|\\-*-/|",
               "unicode" => "Sosa did fine.☺"
             }

      assert doc4 == "Mark McGwire's year was crippled by a knee injury.\n"
    end

    test "detailed: true -- returns AST", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml, detailed: true)
      assert [doc1, doc2, doc3, doc4] = result

      assert doc1 == %YAML.AST.Document{
               root: %YAML.AST.Mapping{
                 pairs: [
                   {%YAML.AST.Scalar{
                      value: "name",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 4, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "Rizu",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 4, column: 7}
                    }},
                   {%YAML.AST.Scalar{
                      value: "age",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 5, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: 25,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:int", line: 5, column: 6}
                    }},
                   {%YAML.AST.Scalar{
                      value: "price",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 6, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: 99.99,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:float", line: 6, column: 8}
                    }},
                   {%YAML.AST.Scalar{
                      value: "active",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 8, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: true,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:bool", line: 8, column: 9}
                    }},
                   {%YAML.AST.Scalar{
                      value: "disabled",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 9, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: false,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:bool", line: 9, column: 11}
                    }},
                   {%YAML.AST.Scalar{
                      value: "middle_name",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 11, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: nil,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:null", line: 11, column: 14}
                    }},
                   {%YAML.AST.Scalar{
                      value: "empty_field",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 12, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: nil,
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:null", line: 12, column: 14}
                    }},
                   {%YAML.AST.Scalar{
                      value: "created_date",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 15, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "2025-01-01",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 15, column: 15}
                    }},
                   {%YAML.AST.Scalar{
                      value: "created_at",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 16, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "2025-01-01T12:30:45Z",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 16, column: 13}
                    }},
                   {%YAML.AST.Scalar{
                      value: "ipv4",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 19, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "192.168.1.10",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 19, column: 7}
                    }},
                   {%YAML.AST.Scalar{
                      value: "ipv6",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 20, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 20, column: 7}
                    }},
                   {%YAML.AST.Scalar{
                      value: "binary_data",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 23, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "Hello WORLD",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:binary", line: 23, column: 23}
                    }},
                   {%YAML.AST.Scalar{
                      value: "skills",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 27, column: 1}
                    },
                    %YAML.AST.List{
                      items: [
                        %YAML.AST.Scalar{
                          value: "Elixir",
                          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 28, column: 5}
                        },
                        %YAML.AST.Scalar{
                          value: "JavaScript",
                          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 29, column: 5}
                        },
                        %YAML.AST.Scalar{
                          value: "Docker",
                          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 30, column: 5}
                        }
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:seq", line: 28, column: 3},
                      length: 3
                    }},
                   {%YAML.AST.Scalar{
                      value: "address",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 33, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "city",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 34, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "Lahore",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 34, column: 9}
                         }},
                        {%YAML.AST.Scalar{
                           value: "zip",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 35, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 54000,
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:int", line: 35, column: 8}
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 34, column: 3}
                    }}
                 ],
                 meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 4, column: 1}
               }
             }

      assert doc2 == %YAML.AST.Document{
               root: %YAML.AST.Mapping{
                 pairs: [
                   {%YAML.AST.Scalar{
                      value: "users",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 40, column: 1}
                    },
                    %YAML.AST.List{
                      items: [
                        %YAML.AST.Mapping{
                          pairs: [
                            {%YAML.AST.Scalar{
                               value: "id",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 41,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: 1,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:int",
                                 line: 41,
                                 column: 9
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "name",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 42,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "Ali",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 42,
                                 column: 11
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "active",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 43,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: true,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:bool",
                                 line: 43,
                                 column: 13
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "last_login",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 44,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "2025-01-05T08:00:00Z",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 44,
                                 column: 17
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "ip",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 45,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "10.0.0.5",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 45,
                                 column: 9
                               }
                             }}
                          ],
                          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 41, column: 5}
                        },
                        %YAML.AST.Mapping{
                          pairs: [
                            {%YAML.AST.Scalar{
                               value: "id",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 46,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: 2,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:int",
                                 line: 46,
                                 column: 9
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "name",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 47,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "Sara",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 47,
                                 column: 11
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "active",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 48,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: false,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:bool",
                                 line: 48,
                                 column: 13
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "email",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 49,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: nil,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:null",
                                 line: 49,
                                 column: 12
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "last_login",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 50,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: nil,
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:null",
                                 line: 50,
                                 column: 17
                               }
                             }},
                            {%YAML.AST.Scalar{
                               value: "ip",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 51,
                                 column: 5
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "10.0.0.8",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 51,
                                 column: 9
                               }
                             }}
                          ],
                          meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 46, column: 5}
                        }
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:seq", line: 41, column: 3},
                      length: 2
                    }},
                   {%YAML.AST.Scalar{
                      value: "project",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 54, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "name",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 55, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "YAML Demo",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 55, column: 9}
                         }},
                        {%YAML.AST.Scalar{
                           value: "tags",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 56, column: 3}
                         },
                         %YAML.AST.List{
                           items: [
                             %YAML.AST.Scalar{
                               value: "config",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 57,
                                 column: 7
                               }
                             },
                             %YAML.AST.Scalar{
                               value: "example",
                               meta: %YAML.AST.Meta{
                                 tag: "tag:yaml.org,2002:str",
                                 line: 58,
                                 column: 7
                               }
                             }
                           ],
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:seq", line: 57, column: 5},
                           length: 2
                         }},
                        {%YAML.AST.Scalar{
                           value: "meta",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 59, column: 3}
                         },
                         %YAML.AST.Mapping{
                           pairs: [
                             {%YAML.AST.Scalar{
                                value: "version",
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:str",
                                  line: 60,
                                  column: 5
                                }
                              },
                              %YAML.AST.Scalar{
                                value: 1.0,
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:float",
                                  line: 60,
                                  column: 14
                                }
                              }},
                             {%YAML.AST.Scalar{
                                value: "published",
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:str",
                                  line: 61,
                                  column: 5
                                }
                              },
                              %YAML.AST.Scalar{
                                value: false,
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:bool",
                                  line: 61,
                                  column: 16
                                }
                              }},
                             {%YAML.AST.Scalar{
                                value: "build_time",
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:str",
                                  line: 62,
                                  column: 5
                                }
                              },
                              %YAML.AST.Scalar{
                                value: "2025-01-10T14:22:00Z",
                                meta: %YAML.AST.Meta{
                                  tag: "tag:yaml.org,2002:str",
                                  line: 62,
                                  column: 17
                                }
                              }}
                           ],
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 60, column: 5}
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 55, column: 3}
                    }}
                 ],
                 meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 40, column: 1}
               }
             }

      assert doc3 == %YAML.AST.Document{
               root: %YAML.AST.Mapping{
                 pairs: [
                   {%YAML.AST.Scalar{
                      value: "description",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 67, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "This is line one\nThis is line two\n",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 67, column: 14}
                    }},
                   {%YAML.AST.Scalar{
                      value: "defaults",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 72, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "retries",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 73, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 3,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 73,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "timeout",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 74, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 30,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 74,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "created_at",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 75, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "2025-01-01T00:00:00Z",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 75,
                             column: 15
                           }
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 73, column: 3}
                    }},
                   {%YAML.AST.Scalar{
                      value: "service_a",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 77, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "retries",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 73, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 3,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 73,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "timeout",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 74, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 30,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 74,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "created_at",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 75, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "2025-01-01T00:00:00Z",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 75,
                             column: 15
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "url",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 79, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "https://api.service-a.com",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 79, column: 8}
                         }},
                        {%YAML.AST.Scalar{
                           value: "ip",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 80, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "172.16.0.1",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 80, column: 7}
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 78, column: 3}
                    }},
                   {%YAML.AST.Scalar{
                      value: "service_b",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 82, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "retries",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 73, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 3,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 73,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "timeout",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 74, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: 30,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 74,
                             column: 12
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "created_at",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 75, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "2025-01-01T00:00:00Z",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 75,
                             column: 15
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "url",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 84, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "https://api.service-b.com",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 84, column: 8}
                         }},
                        {%YAML.AST.Scalar{
                           value: "ip",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 85, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "172.16.0.2",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 85, column: 7}
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 83, column: 3}
                    }},
                   {%YAML.AST.Scalar{
                      value: "misc",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 88, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "yes_value",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 89, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "yes",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 89,
                             column: 14
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "no_value",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 90, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: "no",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 90,
                             column: 13
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "infinity",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 91, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: :"+inf",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:float",
                             line: 91,
                             column: 13
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "not_a_number",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 92, column: 3}
                         },
                         %YAML.AST.Scalar{
                           value: :nan,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:float",
                             line: 92,
                             column: 17
                           }
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 89, column: 3}
                    }},
                   {%YAML.AST.Scalar{
                      value: "Mark McGwire",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 94, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "hr",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 94,
                             column: 16
                           }
                         },
                         %YAML.AST.Scalar{
                           value: 65,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:int",
                             line: 94,
                             column: 20
                           }
                         }},
                        {%YAML.AST.Scalar{
                           value: "avg",
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:str",
                             line: 94,
                             column: 24
                           }
                         },
                         %YAML.AST.Scalar{
                           value: 0.278,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:float",
                             line: 94,
                             column: 29
                           }
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 94, column: 15}
                    }},
                   {%YAML.AST.Scalar{
                      value: "Sammy Sosa",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 95, column: 1}
                    },
                    %YAML.AST.Mapping{
                      pairs: [
                        {%YAML.AST.Scalar{
                           value: "hr",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 96, column: 5}
                         },
                         %YAML.AST.Scalar{
                           value: 63,
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:int", line: 96, column: 9}
                         }},
                        {%YAML.AST.Scalar{
                           value: "avg",
                           meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 97, column: 5}
                         },
                         %YAML.AST.Scalar{
                           value: 0.288,
                           meta: %YAML.AST.Meta{
                             tag: "tag:yaml.org,2002:float",
                             line: 97,
                             column: 10
                           }
                         }}
                      ],
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 95, column: 13}
                    }},
                   {%YAML.AST.Scalar{
                      value: "unicode",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 101, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "Sosa did fine.☺",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 101, column: 10}
                    }},
                   {%YAML.AST.Scalar{
                      value: "control",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 102, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "\b1998\t1999\t2000\n",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 102, column: 10}
                    }},
                   {%YAML.AST.Scalar{
                      value: "hex esc",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 103, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "\r\n is \r\n",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 103, column: 10}
                    }},
                   {%YAML.AST.Scalar{
                      value: "single",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 105, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "\"Howdy!\" he cried.",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 105, column: 9}
                    }},
                   {%YAML.AST.Scalar{
                      value: "quoted",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 106, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: " # Not a 'comment'.",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 106, column: 9}
                    }},
                   {%YAML.AST.Scalar{
                      value: "tie-fighter",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 107, column: 1}
                    },
                    %YAML.AST.Scalar{
                      value: "|\\-*-/|",
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:str", line: 107, column: 14}
                    }}
                 ],
                 meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:map", line: 67, column: 1}
               }
             }

      assert doc4 == %YAML.AST.Document{
               root: %YAML.AST.Scalar{
                 meta: %YAML.AST.Meta{column: 5, line: 109, tag: "tag:yaml.org,2002:str"},
                 value: "Mark McGwire's year was crippled by a knee injury.\n"
               }
             }
    end

    test "detailed: false -- returns simple response", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml)
      assert {:ok, ^result} = YAML.decode(yaml, detailed: false)
      assert [doc1, doc2, doc3, doc4] = result

      assert doc1 == %{
               "active" => true,
               "address" => %{"city" => "Lahore", "zip" => 54000},
               "age" => 25,
               "binary_data" => "Hello WORLD",
               "created_at" => "2025-01-01T12:30:45Z",
               "created_date" => "2025-01-01",
               "disabled" => false,
               "empty_field" => nil,
               "ipv4" => "192.168.1.10",
               "ipv6" => "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
               "middle_name" => nil,
               "name" => "Rizu",
               "price" => 99.99,
               "skills" => ["Elixir", "JavaScript", "Docker"]
             }

      assert doc2 == %{
               "project" => %{
                 "meta" => %{
                   "build_time" => "2025-01-10T14:22:00Z",
                   "published" => false,
                   "version" => 1.0
                 },
                 "name" => "YAML Demo",
                 "tags" => ["config", "example"]
               },
               "users" => [
                 %{
                   "active" => true,
                   "id" => 1,
                   "ip" => "10.0.0.5",
                   "last_login" => "2025-01-05T08:00:00Z",
                   "name" => "Ali"
                 },
                 %{
                   "active" => false,
                   "email" => nil,
                   "id" => 2,
                   "ip" => "10.0.0.8",
                   "last_login" => nil,
                   "name" => "Sara"
                 }
               ]
             }

      assert doc3 == %{
               "defaults" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30
               },
               "description" => "This is line one\nThis is line two\n",
               "misc" => %{
                 "infinity" => :"+inf",
                 "no_value" => "no",
                 "not_a_number" => :nan,
                 "yes_value" => "yes"
               },
               "service_a" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.1",
                 "url" => "https://api.service-a.com"
               },
               "service_b" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.2",
                 "url" => "https://api.service-b.com"
               },
               "Mark McGwire" => %{"avg" => 0.278, "hr" => 65},
               "Sammy Sosa" => %{"avg" => 0.288, "hr" => 63},
               "control" => "\b1998\t1999\t2000\n",
               "hex esc" => "\r\n is \r\n",
               "quoted" => " # Not a 'comment'.",
               "single" => "\"Howdy!\" he cried.",
               "tie-fighter" => "|\\-*-/|",
               "unicode" => "Sosa did fine.☺"
             }

      assert doc4 == "Mark McGwire's year was crippled by a knee injury.\n"
    end

    test "returns error for invalid :detailed option", %{yaml: yaml} do
      assert {:error, %YAML.ArgumentError{option: :detailed, value: "true"}} =
               YAML.decode(yaml, detailed: "true")

      assert_raise YAML.ArgumentError, fn ->
        YAML.decode!(yaml, detailed: "true")
      end
    end

    test "returns error for unknown option", %{yaml: yaml} do
      assert {:error, %YAML.ArgumentError{option: :unknown_option, value: nil}} =
               YAML.decode(yaml, unknown_option: :value)

      assert_raise YAML.ArgumentError, fn ->
        YAML.decode!(yaml, unknown_option: :value)
      end
    end

    test "returns error for invalid :return option", %{yaml: yaml} do
      assert {:error, %YAML.ArgumentError{option: :return, value: :invalid}} =
               YAML.decode(yaml, return: :invalid)

      assert_raise YAML.ArgumentError, fn ->
        YAML.decode!(yaml, return: :invalid)
      end
    end

    test "enable_merge: true -- returns merged response", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml)
      assert {:ok, ^result} = YAML.decode(yaml, enable_merge: true)
      assert [_doc1, _doc2, doc3, _doc4] = result

      assert doc3 == %{
               "defaults" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30
               },
               "description" => "This is line one\nThis is line two\n",
               "misc" => %{
                 "infinity" => :"+inf",
                 "no_value" => "no",
                 "not_a_number" => :nan,
                 "yes_value" => "yes"
               },
               "service_a" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.1",
                 "url" => "https://api.service-a.com"
               },
               "service_b" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30,
                 "ip" => "172.16.0.2",
                 "url" => "https://api.service-b.com"
               },
               "Mark McGwire" => %{"avg" => 0.278, "hr" => 65},
               "Sammy Sosa" => %{"avg" => 0.288, "hr" => 63},
               "control" => "\b1998\t1999\t2000\n",
               "hex esc" => "\r\n is \r\n",
               "quoted" => " # Not a 'comment'.",
               "single" => "\"Howdy!\" he cried.",
               "tie-fighter" => "|\\-*-/|",
               "unicode" => "Sosa did fine.☺"
             }
    end

    test "enable_merge: false -- returns data as simple map", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml, enable_merge: false)
      assert [_doc1, _doc2, doc3, _doc4] = result

      assert doc3 == %{
               "defaults" => %{
                 "created_at" => "2025-01-01T00:00:00Z",
                 "retries" => 3,
                 "timeout" => 30
               },
               "description" => "This is line one\nThis is line two\n",
               "misc" => %{
                 "infinity" => :"+inf",
                 "no_value" => "no",
                 "not_a_number" => :nan,
                 "yes_value" => "yes"
               },
               "service_a" => %{
                 "<<" => %{
                   "created_at" => "2025-01-01T00:00:00Z",
                   "retries" => 3,
                   "timeout" => 30
                 },
                 "ip" => "172.16.0.1",
                 "url" => "https://api.service-a.com"
               },
               "service_b" => %{
                 "<<" => %{
                   "created_at" => "2025-01-01T00:00:00Z",
                   "retries" => 3,
                   "timeout" => 30
                 },
                 "ip" => "172.16.0.2",
                 "url" => "https://api.service-b.com"
               },
               "Mark McGwire" => %{"avg" => 0.278, "hr" => 65},
               "Sammy Sosa" => %{"avg" => 0.288, "hr" => 63},
               "control" => "\b1998\t1999\t2000\n",
               "hex esc" => "\r\n is \r\n",
               "quoted" => " # Not a 'comment'.",
               "single" => "\"Howdy!\" he cried.",
               "tie-fighter" => "|\\-*-/|",
               "unicode" => "Sosa did fine.☺"
             }
    end

    test "enable_merge: true -- respects merge order", %{merge_yaml: merge_yaml} do
      assert {:ok, result} = YAML.decode(merge_yaml)
      assert {:ok, ^result} = YAML.decode(merge_yaml, enable_merge: true)
      assert [doc1] = result

      assert doc1 ==
               %{
                 "service_x" => %{
                   "name" => "service_x",
                   "critical" => false,
                   "timeout" => 100,
                   "javascript" => "nodejs"
                 },
                 "service_y" => %{
                   "name" => "service_y",
                   "critical" => true,
                   "timeout" => 500,
                   "elixir" => "phoenix"
                 },
                 "service_z" => %{
                   "name" => "service_z",
                   "level_1" => %{
                     "rust" => "rocket",
                     "level_2" => %{
                       "nested" => "so_deep"
                     }
                   }
                 },
                 "node_1" => %{
                   "name" => "node_1",
                   "critical" => false,
                   "timeout" => 100,
                   "javascript" => "nodejs"
                 },
                 "node_2" => %{
                   "name" => "should_be_overridden",
                   "critical" => true,
                   "timeout" => 300,
                   "elixir" => "phoenix"
                 },
                 "node_3" => %{
                   "name" => "node_3",
                   "critical" => false,
                   "timeout" => 100,
                   "elixir" => "phoenix",
                   "javascript" => "nodejs"
                 },
                 "node_4" => %{
                   "name" => "node_4",
                   "critical" => false,
                   "timeout" => 100,
                   # NOTE: Yamerl parser limitation - when multiple << keys appear in sequence:
                   #   <<: *service_y
                   #   <<: *service_x
                   # Yamerl only processes the last << key (*service_x) and ignores the rest.
                   # This means keys from service_y (like "elixir") won't be included, but
                   # keys from service_x (like "javascript") will be present in the merged result.
                   #
                   # Workaround: Use array syntax instead: <<: [*service_x, *service_y]
                   # "elixir" => "phoenix",
                   "javascript" => "nodejs"
                 },
                 "node_5" => %{
                   "name" => "node_5",
                   "critical" => false,
                   "timeout" => 100,
                   "javascript" => "nodejs",
                   "nested" => %{
                     "name" => "nested",
                     "critical" => true,
                     "timeout" => 500,
                     "elixir" => "phoenix"
                   },
                   "deep_nested" => %{
                     "name" => "service_z",
                     "level_1" => %{
                       "rust" => "yew",
                       "level_2" => %{
                         "complex" => true
                       }
                     }
                   }
                 },
                 "node_7" => [
                   %{
                     "name" => "node_7_first",
                     "critical" => false,
                     "timeout" => 100,
                     "javascript" => "nodejs"
                   },
                   %{
                     "name" => "node_7_second",
                     "critical" => true,
                     "timeout" => 500,
                     "javascript" => "nodejs",
                     "elixir" => "phoenix"
                   },
                   %{
                     "name" => "node_7_third",
                     "level_1" => %{
                       "rust" => "yew"
                     },
                     "critical" => true,
                     "timeout" => 500,
                     "elixir" => "phoenix"
                   }
                 ]
               }
    end
  end
end
