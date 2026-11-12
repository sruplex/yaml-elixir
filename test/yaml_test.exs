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
                      meta: %YAML.AST.Meta{tag: "tag:yaml.org,2002:binary", line: 23, column: 14}
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
      assert {:error,
              %YAML.ArgumentError{
                message: "unknown option :unknown_option",
                option: :unknown_option,
                value: :value
              }} = YAML.decode(yaml, unknown_option: :value)

      assert_raise YAML.ArgumentError, fn ->
        YAML.decode!(yaml, unknown_option: :value)
      end
    end

    test "return: :auto returns the document itself for single-document input" do
      assert {:ok, %{"a" => 1}} = YAML.decode("a: 1")
      assert {:ok, ["x", "y"]} = YAML.decode("- x\n- y")
      assert {:ok, nil} = YAML.decode("")
    end

    test "return: :auto returns a list for multi-document input" do
      assert {:ok, [%{"a" => 1}, %{"b" => 2}]} = YAML.decode("a: 1\n---\nb: 2")
    end

    test "return: :all_documents always returns a list" do
      assert {:ok, [%{"a" => 1}]} = YAML.decode("a: 1", return: :all_documents)
    end

    test "return: :first_document returns nil for empty input" do
      assert {:ok, nil} = YAML.decode("", return: :first_document)
      assert YAML.decode!("", return: :first_document) == nil

      # :all_documents tells an empty input apart from a null document
      assert {:ok, []} = YAML.decode("", return: :all_documents)
      assert {:ok, [nil]} = YAML.decode("~", return: :all_documents)
    end

    test "an error at the end of the input is at the end of the last line" do
      for yaml <- ["a: [1, 2", "a: [1, 2\n", "x: 1\na: {k: 1", "x: 1\r\na: {k: 1\r\n"] do
        line = if String.starts_with?(yaml, "x"), do: 2, else: 1
        assert {:error, %YAML.ParsingError{location: {^line, 9}}} = YAML.decode(yaml)
      end
    end

    test "reads numbers as the YAML 1.2 core and YAML 1.1 schemas type them" do
      for {text, core, yaml11} <- [
            {"+0o7", "+0o7", "+0o7"},
            {"-0x1F", "-0x1F", -31},
            {"0x", "0x", "0x"},
            {"0b", "0b", "0b"},
            {"1e3", 1000.0, "1e3"},
            {"0.1e1", 1.0, "0.1e1"},
            {"0.1e+1", 1.0, 1.0},
            {"685_230.15", "685_230.15", 685_230.15},
            {"685.230_15e+03", "685.230_15e+03", 685_230.15},
            {".1_0", ".1_0", 0.1}
          ] do
        assert YAML.decode!("k: " <> text)["k"] == core, "core #{text}"
        assert YAML.decode!("k: " <> text, schema: :yaml11)["k"] == yaml11, "yaml11 #{text}"
      end
    end

    test "a JSON float too large for a float is an error" do
      assert {:error, %YAML.ParsingError{message: "invalid float"}} =
               YAML.decode("1e400", schema: :json)
    end

    test "an alias to an anchor in an earlier document is an error" do
      assert {:error, %YAML.ParsingError{message: "unknown anchor"}} =
               YAML.decode("--- &a 1\n--- *a\n", return: :all_documents)
    end

    test "!!int reads integers in any base" do
      for {text, int} <- [
            {"12", 12},
            {"+12", 12},
            {"0x1F", 31},
            {"-0x1F", -31},
            {"0o17", 15},
            {"1_000", 1000}
          ] do
        assert YAML.decode!("k: !!int " <> text)["k"] == int, text
      end

      assert {:error, %YAML.ParsingError{message: "invalid integer"}} =
               YAML.decode("k: !!int 1.5")
    end

    test "YAML.Parser.parse/2 takes a schema atom" do
      assert {:ok, [%YAML.AST.Document{root: %{value: true}}]} = YAML.Parser.parse("yes", :yaml11)
    end

    test "small and large inputs decode the same" do
      doc = "a: [1, 2]\nb: {c: d}\n"
      large = String.duplicate(doc <> "---\n", 1_000)
      assert byte_size(doc) < 2_000 and byte_size(large) > 2_000

      assert {:ok, documents} = YAML.decode(large, return: :all_documents, detailed: true)
      assert {:ok, [first]} = YAML.decode(doc, return: :all_documents, detailed: true)
      assert hd(documents) == first
      assert hd(YAML.decode!(large, return: :all_documents)) == YAML.decode!(doc)
    end

    test "a large input is parsed a slice at a time" do
      huge = String.duplicate("---\na: [1, 2]\nb: {c: d}\n", 50_000)
      assert {:cont, _job} = YAML.Native.parse(huge, :core, :ast)
      assert length(YAML.decode!(huge, return: :all_documents)) == 50_000
    end

    test "aliases share their anchor's value instead of copying it" do
      text = String.duplicate("x", 100_000)

      yaml =
        "a: &a #{text}\nm: &m {k: [1, 2]}\nb: [#{Enum.map_join(1..1_000, ", ", fn _ -> "*a" end)}]\nc: [*m, *m]\n"

      assert {:ok, %{"a" => a, "b" => b, "m" => m, "c" => [m1, m2]}} = YAML.decode(yaml)
      assert length(b) == 1_000 and Enum.all?(b, &:erts_debug.same(&1, hd(b)))
      assert hd(b) == a and m1 == m and :erts_debug.same(m1, m2)
    end

    test "aliases that expand a small file into too many values are an error" do
      first = "a: &a [x, x, x, x, x, x, x, x, x, x]\n"

      bomb =
        Enum.map_join(?b..?h, "", fn c ->
          "#{<<c>>}: &#{<<c>>} [#{Enum.map_join(1..10, ", ", fn _ -> "*#{<<c - 1>>}" end)}]\n"
        end)

      assert {:error, %YAML.ParsingError{message: "aliases expand to too many values"}} =
               YAML.decode(first <> bomb)
    end

    test "many aliases in a large file are not an error" do
      yaml =
        "defaults: &d {a: 1, b: 2}\nitems:\n" <>
          Enum.map_join(1..50_000, "", &"  - {id: #{&1}, n: 1, m: 2, o: 3}\n  - *d\n")

      assert {:ok, %{"items" => items}} = YAML.decode(yaml)
      assert length(items) == 100_000
    end

    test "invalid UTF-8 is an error at the first bad byte" do
      assert {:error, %YAML.ParsingError{message: "invalid UTF-8", location: {1, 7}}} =
               YAML.decode(<<"a: caf", 0xE9, "\n">>)

      assert {:error, %YAML.ParsingError{location: {2, 6}}} =
               YAML.decode(<<"x: 1\nb: 日本", 0xE6, 0x97, "\n">>)
    end

    test "a list entry on a key's line is an error" do
      assert {:error, %YAML.ParsingError{location: {1, 4}}} = YAML.decode("k: -")
    end

    test "returns error for an invalid :schema option" do
      assert {:error, %YAML.ArgumentError{option: :schema, value: :yaml12}} =
               YAML.decode("a: 1", schema: :yaml12)
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

    test "enable_merge: true -- merges maps holding any value" do
      yaml =
        "base: &b\n  big: 123456789012345678901234567890\n  atom: .inf\n  list: [1, [2]]\nx:\n  <<: *b\n  y: 1\n"

      base = %{
        "big" => 123_456_789_012_345_678_901_234_567_890,
        "atom" => :"+inf",
        "list" => [1, [2]]
      }

      assert YAML.decode!(yaml) == %{"base" => base, "x" => Map.put(base, "y", 1)}
    end

    test "enable_merge: true -- respects merge order", %{merge_yaml: merge_yaml} do
      assert {:ok, result} = YAML.decode(merge_yaml)
      assert {:ok, ^result} = YAML.decode(merge_yaml, enable_merge: true)
      assert %{} = doc1 = result

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
                   "elixir" => "phoenix",
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

    test "atomize_keys: false -- keeps keys as binary strings (default)", %{yaml: yaml} do
      assert {:ok, result} = YAML.decode(yaml)
      assert {:ok, ^result} = YAML.decode(yaml, atomize_keys: false)
      assert [doc1, doc2, doc3, _doc4] = result

      assert doc1 |> Map.keys() |> Enum.all?(&is_binary/1)
      assert doc2 |> Map.keys() |> Enum.all?(&is_binary/1)
      assert doc3 |> Map.keys() |> Enum.all?(&is_binary/1)
    end

    test "atomize_keys: :safe -- converts only existing atoms", %{yaml: _yaml} do
      yaml = """
      name: "Rizu"
      ag1e: 25
      pricine: 99.99
      skillsm:
        - Elixir
        - JavaScript
        - Docker
      """

      {:ok, doc1} = YAML.decode(yaml, atomize_keys: :safe)

      # :name already exists as atom in another yaml
      assert doc1[:name] == "Rizu"

      # Unknown keys stay strings
      assert doc1["ag1e"] == 25
      assert doc1["pricine"] == 99.99
      assert doc1["skillsm"] == ["Elixir", "JavaScript", "Docker"]
    end

    test "atomize_keys: true -- converts all keys to atoms", %{yaml: yaml} do
      {:ok, result} = YAML.decode(yaml, atomize_keys: true)
      assert [doc1, doc2, doc3, _doc4] = result

      assert doc1 |> Map.keys() |> Enum.all?(&is_atom/1)
      assert doc2 |> Map.keys() |> Enum.all?(&is_atom/1)
      assert doc3 |> Map.keys() |> Enum.all?(&is_atom/1)
    end
  end

  describe "encode/2" do
    test "encodes Elixir data" do
      assert YAML.encode(%{"a" => 1, "b" => [true, nil]}) ==
               {:ok, "---\na: 1\nb:\n  - true\n  - null\n"}

      assert YAML.encode("a\nb\n") == {:ok, "---\n|\n  a\n  b\n"}
      assert YAML.encode(nil) == {:ok, "---\nnull\n"}
    end

    test "decodes back to the same data" do
      values = [
        %{"name" => "Ali", "tags" => ["a", "b"], "port" => 4000, "ratio" => 1.5},
        [%{"run" => "mix deps.get\nmix test\n"}, %{}, []],
        %{"yes" => "no", "123" => "", "nested" => %{"deep" => [[1, 2], nil]}},
        "plain string",
        42
      ]

      for value <- values do
        assert value |> YAML.encode!() |> YAML.decode!() == value
      end
    end

    test "encodes a decoded AST document back to the same YAML data" do
      yaml = "a: 1\nb:\n  - x\n  - c: true\n"
      assert {:ok, document} = YAML.decode(yaml, detailed: true)
      assert {:ok, encoded} = YAML.encode(document)
      assert YAML.decode(encoded) == YAML.decode(yaml)
    end

    test "encodes a list of documents as multiple documents" do
      yaml = "a: 1\n---\n- 2\n"
      assert {:ok, documents} = YAML.decode(yaml, detailed: true)
      assert {:ok, encoded} = YAML.encode(documents)
      assert encoded == "---\na: 1\n---\n- 2\n"
      assert YAML.decode(encoded) == {:ok, [%{"a" => 1}, [2]]}
    end

    test "returns an error for values that can't be encoded" do
      assert {:error, %YAML.EncodeError{type: :unsupported_type}} = YAML.encode({1, 2})
      assert {:error, %YAML.EncodeError{type: :invalid_key}} = YAML.encode(%{{1} => 2})

      assert {:error, %YAML.EncodeError{message: "cannot encode invalid UTF-8 string"}} =
               YAML.encode(%{"a" => <<255>>})
    end

    test "an empty list is plain data, not an empty list of documents" do
      assert YAML.encode([]) == {:ok, "---\n[]\n"}
    end

    test "a list of documents round-trips through a detailed decode" do
      yaml = "---\na: [1, 2]\n---\nx\n---\n|\n  a\n  b\n"
      assert {:ok, documents} = YAML.decode(yaml, detailed: true, return: :all_documents)
      assert {:ok, encoded} = YAML.encode(documents)

      assert YAML.decode(encoded, return: :all_documents) ==
               {:ok, [%{"a" => [1, 2]}, "x", "a\nb\n"]}
    end

    test "a list with one document is a single document" do
      assert {:ok, document} = YAML.decode("a: 1", detailed: true)
      assert YAML.encode([document]) == {:ok, "---\na: 1\n"}
    end

    test "a list starting with other data is plain data" do
      assert {:ok, document} = YAML.decode("a: 1", detailed: true)

      assert {:error,
              %YAML.EncodeError{
                message: "cannot encode YAML.AST.Document struct without a YAML.Encoder",
                location: [1]
              }} =
               YAML.encode([1, document])
    end

    test "a keyword list is not encoded, since tuples are not supported" do
      keyword = [foo: 1, bar: 2]

      assert {:error, %YAML.EncodeError{message: "cannot encode tuple", location: [0]}} =
               YAML.encode(keyword)
    end

    test "returns an error for unknown options" do
      assert {:error, %YAML.ArgumentError{message: "unknown option :foo", option: :foo, value: 1}} =
               YAML.encode(%{}, foo: 1)
    end

    test "returns an error for options that are not a keyword list" do
      for {opts, bad} <- [{[:foo], :foo}, {[{"x", 1}], {"x", 1}}] do
        assert {:error,
                %YAML.ArgumentError{message: "expected a keyword list", option: nil, value: ^bad}} =
                 YAML.encode(%{}, opts)
      end
    end

    test "sort_maps: true writes map keys in sorted order" do
      value = %{z: 1, a: %{"x" => 2, "b" => 3}, m: [%{c: 4, b: 5}]}

      assert YAML.encode(value, sort_maps: true) ==
               {:ok, "---\na:\n  b: 3\n  x: 2\nm:\n  - b: 5\n    c: 4\nz: 1\n"}

      big = Map.new(1..40, &{"k#{String.pad_leading(Integer.to_string(&1), 2, "0")}", &1})
      keys = big |> YAML.encode!(sort_maps: true) |> String.split("\n", trim: true) |> tl()

      assert keys ==
               Enum.map(1..40, &"k#{String.pad_leading(Integer.to_string(&1), 2, "0")}: #{&1}")
    end

    test "sort_maps: true also sorts the keys of a map key" do
      value = %{%{[1] => 1, z: 2, a: 3} => 1}

      assert YAML.encode(value, sort_maps: true) ==
               {:ok, "---\n? ? - 1\n  : 1\n  a: 3\n  z: 2\n: 1\n"}
    end

    test "without sort_maps, map keys follow Elixir's map order" do
      value = %{c: 1, a: 2, b: 3}
      lines = value |> YAML.encode!() |> String.split("\n", trim: true) |> tl()
      assert lines == Enum.map(Map.to_list(value), fn {k, v} -> "#{k}: #{v}" end)
    end

    test "sort_maps must be a boolean" do
      assert {:error, %YAML.ArgumentError{option: :sort_maps, message: "must be a boolean"}} =
               YAML.encode(%{}, sort_maps: :yes)
    end

    test "dates and times are written as quoted ISO 8601 strings" do
      assert YAML.encode(%{"d" => ~D[2024-01-02]}) == {:ok, ~s(---\nd: "2024-01-02"\n)}
      assert YAML.decode!(YAML.encode!(%{"d" => ~D[2024-01-02]})) == %{"d" => "2024-01-02"}
    end

    test "an error at the top has a plain message" do
      assert {:error, error} = YAML.encode({1, 2})
      assert error.location == []
      assert Exception.message(error) == "cannot encode tuple"
    end
  end

  describe "encode!/2" do
    test "returns the YAML or raises" do
      assert YAML.encode!(%{"a" => 1}) == "---\na: 1\n"
      assert_raise YAML.EncodeError, "cannot encode tuple", fn -> YAML.encode!({1, 2}) end
      assert_raise YAML.ArgumentError, "unknown option :foo", fn -> YAML.encode!(%{}, foo: 1) end
    end

    test "raises with the location" do
      assert_raise YAML.EncodeError, ~s{cannot encode pid (at ["a", 1])}, fn ->
        YAML.encode!(%{"a" => [1, self()]})
      end
    end
  end

  describe "encode/2 error locations" do
    test "nested errors say where the value is" do
      assert {:error, %YAML.EncodeError{location: ["servers", 0, "port"]} = error} =
               YAML.encode(%{"servers" => [%{"port" => {1, 2}}]})

      assert Exception.message(error) == ~s{cannot encode tuple (at ["servers", 0, "port"])}
    end

    test "errors in a later document start with its index" do
      assert {:ok, documents} = YAML.decode("a: 1\n---\nk: x\n", detailed: true)
      [first, %{root: %{pairs: [{key, value}]} = root} = second] = documents
      second = %{second | root: %{root | pairs: [{key, %{value | value: <<255>>}}]}}

      assert {:error, %YAML.EncodeError{location: [1, "k"]}} = YAML.encode([first, second])
    end
  end

  describe "encode_to_iodata/2" do
    test "returns the same YAML as iodata" do
      assert {:ok, iodata} = YAML.encode_to_iodata(%{"a" => [1, 2]})
      assert IO.iodata_to_binary(iodata) == YAML.encode!(%{"a" => [1, 2]})
    end

    test "returns errors like encode/2" do
      assert {:error, %YAML.EncodeError{}} = YAML.encode_to_iodata({1, 2})
      assert {:error, %YAML.ArgumentError{}} = YAML.encode_to_iodata(%{}, foo: 1)
    end
  end

  describe "encode_to_iodata!/2" do
    test "returns iodata or raises" do
      assert "---\na: 1\n" == %{"a" => 1} |> YAML.encode_to_iodata!() |> IO.iodata_to_binary()
      assert_raise YAML.EncodeError, fn -> YAML.encode_to_iodata!({1, 2}) end
      assert_raise YAML.ArgumentError, fn -> YAML.encode_to_iodata!(%{}, foo: 1) end
    end
  end

  describe "encode_stream/2" do
    test "yields an ok tuple for each item" do
      assert [%{"a" => 1}, [1, 2]]
             |> YAML.encode_stream()
             |> Enum.map(fn {:ok, iodata} -> IO.iodata_to_binary(iodata) end) ==
               ["---\na: 1\n", "---\n- 1\n- 2\n"]
    end

    test "yields an error for a bad item and keeps going" do
      assert [
               {:ok, _},
               {:error, %YAML.EncodeError{type: :unsupported_type, location: [1, "a"]}},
               {:ok, _}
             ] = [1, %{"a" => {1, 2}}, 3] |> YAML.encode_stream() |> Enum.to_list()
    end

    test "is lazy" do
      stream = Stream.repeatedly(fn -> %{"a" => 1} end) |> YAML.encode_stream()
      assert [{:ok, _}, {:ok, _}] = Enum.take(stream, 2)
    end

    test "raises on unknown options before encoding" do
      assert_raise YAML.ArgumentError, "unknown option :foo", fn ->
        YAML.encode_stream([1], foo: 1)
      end
    end
  end

  describe "encode_stream!/2" do
    test "encodes each item as one document" do
      stream = YAML.encode_stream!([%{"a" => 1}, [1, 2], "x"])

      assert stream |> Enum.to_list() |> IO.iodata_to_binary() ==
               "---\na: 1\n---\n- 1\n- 2\n---\nx\n"
    end

    test "is lazy" do
      stream = Stream.repeatedly(fn -> %{"a" => 1} end) |> YAML.encode_stream!()
      assert stream |> Enum.take(2) |> IO.iodata_to_binary() == "---\na: 1\n---\na: 1\n"
    end

    test "an empty enumerable gives no documents" do
      assert [] |> YAML.encode_stream!() |> Enum.to_list() == []
    end

    test "writes AST documents as they are" do
      assert {:ok, document} = YAML.decode("a: 1", detailed: true)

      assert [document] |> YAML.encode_stream!() |> Enum.to_list() |> IO.iodata_to_binary() ==
               "---\na: 1\n"
    end

    test "raises with the item index in the location" do
      stream = YAML.encode_stream!([1, %{"a" => {1, 2}}])

      assert_raise YAML.EncodeError, ~s{cannot encode tuple (at [1, "a"])}, fn ->
        Stream.run(stream)
      end
    end

    test "an error inside a document item starts with its index" do
      assert {:ok, document} = YAML.decode("a", detailed: true)
      stream = YAML.encode_stream!([1, %{document | root: %{document.root | value: {:bad}}}])

      assert_raise YAML.EncodeError, "cannot encode tuple (at [1])", fn ->
        Stream.run(stream)
      end
    end

    test "a list of documents as one item is not expanded" do
      assert {:ok, document} = YAML.decode("a: 1", detailed: true)
      stream = YAML.encode_stream!([[document]])

      assert_raise YAML.EncodeError,
                   "cannot encode YAML.AST.Document struct without a YAML.Encoder (at [0, 0])",
                   fn ->
                     Stream.run(stream)
                   end
    end

    test "raises on unknown options before encoding" do
      assert_raise YAML.ArgumentError, "unknown option :foo", fn ->
        YAML.encode_stream!([1], foo: 1)
      end
    end

    test "takes the same options as encode/2" do
      stream = YAML.encode_stream!([%{b: 1, a: 2}], sort_maps: true)
      assert stream |> Enum.to_list() |> IO.iodata_to_binary() == "---\na: 2\nb: 1\n"
    end

    @tag :tmp_dir
    test "streams into a file that decodes back", %{tmp_dir: dir} do
      path = Path.join(dir, "out.yml")
      items = [%{"a" => 1}, %{"b" => [2, 3]}]

      items
      |> YAML.encode_stream!()
      |> Stream.into(File.stream!(path, [:delayed_write]))
      |> Stream.run()

      assert path |> File.read!() |> YAML.decode(return: :all_documents) == {:ok, items}
    end
  end

  describe "fixtures round trip" do
    test "decoding, encoding and decoding again gives the same data" do
      for fixture <- [:multi_document_mixed_types, :merge_example] do
        data = fixture |> Fixtures.read!() |> YAML.decode!()
        assert data |> YAML.encode!() |> YAML.decode!() == data
      end
    end
  end

  describe "decode_stream/2" do
    test "yields an ok tuple for each document" do
      assert ["a: 1\n---\nb: 2\n"] |> YAML.decode_stream() |> Enum.to_list() ==
               [{:ok, %{"a" => 1}}, {:ok, %{"b" => 2}}]
    end

    test "yields an error for a broken document and keeps going" do
      yaml = "a: 1\n---\nb: [1\n---\nc: 3\n"

      assert [{:ok, %{"a" => 1}}, {:error, %YAML.ParsingError{} = error}, {:ok, %{"c" => 3}}] =
               [yaml] |> YAML.decode_stream() |> Enum.to_list()

      # The line counts from the start of the whole stream
      assert {3, _column} = error.location
    end

    test "yields an error for an unclosed flow map and keeps going" do
      assert [{:error, %YAML.ParsingError{}}, {:ok, %{"b" => 1}}] =
               ["d: {x\n---\nb: 1\n"] |> YAML.decode_stream() |> Enum.to_list()
    end

    test "a --- line in a quoted string ends the document, per the YAML spec" do
      assert [{:error, %YAML.ParsingError{location: {1, 4}}}, {:ok, "y\""}] =
               [~s(a: "x\n---\ny")] |> YAML.decode_stream() |> Enum.to_list()
    end

    test "is lazy" do
      stream = Stream.cycle(["---\n", "a: 1\n"]) |> YAML.decode_stream()
      assert Enum.take(stream, 2) == [{:ok, %{"a" => 1}}, {:ok, %{"a" => 1}}]
    end

    test "raises on invalid options before reading" do
      assert_raise YAML.ArgumentError, "unknown option :foo", fn ->
        YAML.decode_stream([], foo: 1)
      end

      assert_raise YAML.ArgumentError, "is not supported when streaming", fn ->
        YAML.decode_stream([], return: :first_document)
      end
    end
  end

  describe "decode_stream!/2" do
    test "decodes one document at a time" do
      assert stream("a: 1\n---\nb: 2\n") == [%{"a" => 1}, %{"b" => 2}]
      assert stream("a: 1\n") == [%{"a" => 1}]
      assert stream("") == []
    end

    test "gives the same documents as decode/2, however the input is cut" do
      for yaml <- [Fixtures.read!(:multi_document_mixed_types), Fixtures.read!(:merge_example)],
          size <- [1, 2, 7, 64, 100_000] do
        assert yaml |> chunked(size) |> YAML.decode_stream!() |> Enum.to_list() ==
                 YAML.decode!(yaml, return: :all_documents)
      end
    end

    test "handles document markers, comments and directives" do
      for yaml <- [
            "# comment\n---\na: 1\n---\nb: 2\n",
            "---\na: 1\n...\n---\nb: 2\n...\n",
            "a: 1\n...\nb: 2\n",
            "%YAML 1.2\n---\na: 1\n...\n%YAML 1.2\n---\nb: 2\n",
            "--- 1\n--- 2\n---\n",
            "---\n---\n",
            "a: |\n  ---\n  x\nb: 2\n---\nc: 3\n",
            "a: 1\r\n---\r\nb: 2\r\n",
            "---\na: 1\n---",
            "a: |\n  x",
            "--- |\nx",
            "a: |+\n  x\n\n",
            "a: 1\n..."
          ] do
        assert stream(yaml) == YAML.decode!(yaml, return: :all_documents), inspect(yaml)
      end
    end

    test "is lazy" do
      documents = Stream.cycle(["---\n", "a: 1\n"]) |> YAML.decode_stream!() |> Enum.take(3)
      assert documents == [%{"a" => 1}, %{"a" => 1}, %{"a" => 1}]
    end

    test "keeps a multi-byte character split across chunks" do
      assert stream(["a: caf", <<0xC3>>, <<0xA9>>, "\n"]) == [%{"a" => "café"}]
    end

    @tag :tmp_dir
    test "reads a file stream", %{tmp_dir: dir} do
      path = Path.join(dir, "test.yml")
      File.write!(path, Enum.map_join(1..100, &"---\nid: #{&1}\n"))

      assert path |> File.stream!() |> YAML.decode_stream!() |> Enum.map(& &1["id"]) ==
               Enum.to_list(1..100)
    end

    test "takes the same options as decode/2" do
      yaml = Fixtures.read!(:merge_example)

      for opts <- [
            [atomize_keys: true],
            [enable_merge: false],
            [schema: :yaml11],
            [detailed: true]
          ] do
        assert stream(yaml, opts) == YAML.decode!(yaml, [return: :all_documents] ++ opts)
      end
    end

    test "line numbers match the whole stream" do
      for yaml <- [
            "a: 1\n---\nb:\n  - x\n---\nc: 3\n",
            "# comment\n---\na: 1\n...\n# comment\n%YAML 1.2\n---\nb:\n  - x\n",
            "a: 1\n---\nb: |\n  x"
          ] do
        assert stream(yaml, detailed: true) ==
                 YAML.decode!(yaml, detailed: true, return: :all_documents),
               inspect(yaml)
      end
    end

    test "places an empty document's null at the end of its --- line" do
      assert [_, %YAML.AST.Document{root: %YAML.AST.Scalar{value: nil} = root}, _] =
               stream("a: 1\n---\n---\nb: 2\n", detailed: true)

      assert {root.meta.line, root.meta.column} == {2, 4}
    end

    test "raises on invalid YAML with the line in the whole stream" do
      error = assert_raise YAML.ParsingError, fn -> stream("a: 1\n---\nb: 2\n---\nc: [1\n") end
      assert error.location == {5, 6}
    end

    test "raises on invalid options before reading" do
      assert_raise YAML.ArgumentError, "unknown option :foo", fn ->
        YAML.decode_stream!([], foo: 1)
      end

      assert_raise YAML.ArgumentError, "is not supported when streaming", fn ->
        YAML.decode_stream!([], return: :first_document)
      end
    end
  end

  # Cuts a string into chunks of `size` bytes, like a file read in blocks
  defp chunked(string, size) do
    whole = div(byte_size(string), size) * size
    chunks = for <<chunk::binary-size(size) <- binary_part(string, 0, whole)>>, do: chunk
    chunks ++ [binary_part(string, whole, byte_size(string) - whole)]
  end

  defp stream(yaml, opts \\ []),
    do: List.wrap(yaml) |> YAML.decode_stream!(opts) |> Enum.to_list()
end
