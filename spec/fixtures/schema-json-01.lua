--[[
    scalar Date

    type User {
        id: ID,
        friends: [User],
        birthday: Date,
        hobbies: [Hobby]
    }

    type Hobby {
        id: ID,
        name: String,
        frequencyPerWeek: Int
    }

    type Query {
        allUsers(pageSize: Int): [User]
        allHobbies(pageSize: Int): [Hobby]
    }

    type Mutation {
        changeHobby(id: ID, name: String, frequencyPerWeek: Int): Hobby
    }
]]


return [[
{
    "__schema": {
      "types": [
        {
          "kind": "OBJECT",
          "name": "Query",
          "ofType": null,
          "fields": [
            {
              "name": "allUsers",
              "args": [
                {
                  "name": "pageSize",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "User",
                  "ofType": null
                }
              }
            },
            {
              "name": "allHobbies",
              "args": [
                {
                  "name": "pageSize",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Hobby",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "Int",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "User",
          "ofType": null,
          "fields": [
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "ID",
                "ofType": null
              }
            },
            {
              "name": "friends",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "User",
                  "ofType": null
                }
              }
            },
            {
              "name": "birthday",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Date",
                "ofType": null
              }
            },
            {
              "name": "hobbies",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Hobby",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "ID",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "Date",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Hobby",
          "ofType": null,
          "fields": [
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "ID",
                "ofType": null
              }
            },
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "frequencyPerWeek",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "String",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Mutation",
          "ofType": null,
          "fields": [
            {
              "name": "changeHobby",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "name",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "frequencyPerWeek",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Hobby",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Schema",
          "ofType": null,
          "fields": [
            {
              "name": "types",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Type",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "queryType",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "mutationType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            },
            {
              "name": "subscriptionType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            },
            {
              "name": "directives",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Directive",
                      "ofType": null
                    }
                  }
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Type",
          "ofType": null,
          "fields": [
            {
              "name": "kind",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "ENUM",
                  "name": "__TypeKind",
                  "ofType": null
                }
              }
            },
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "fields",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Field",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "interfaces",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "possibleTypes",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "enumValues",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__EnumValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "inputFields",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__InputValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "ofType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "ENUM",
          "name": "__TypeKind",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": [
            {
              "name": "SCALAR"
            },
            {
              "name": "OBJECT"
            },
            {
              "name": "INTERFACE"
            },
            {
              "name": "UNION"
            },
            {
              "name": "ENUM"
            },
            {
              "name": "INPUT_OBJECT"
            },
            {
              "name": "LIST"
            },
            {
              "name": "NON_NULL"
            }
          ]
        },
        {
          "kind": "SCALAR",
          "name": "Boolean",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Field",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "args",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__InputValue",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "defaultValue",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__EnumValue",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Directive",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "locations",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "ENUM",
                      "name": "__DirectiveLocation",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "args",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "ENUM",
          "name": "__DirectiveLocation",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": [
            {
              "name": "QUERY"
            },
            {
              "name": "MUTATION"
            },
            {
              "name": "SUBSCRIPTION"
            },
            {
              "name": "FIELD"
            },
            {
              "name": "FRAGMENT_DEFINITION"
            },
            {
              "name": "FRAGMENT_SPREAD"
            },
            {
              "name": "INLINE_FRAGMENT"
            },
            {
              "name": "VARIABLE_DEFINITION"
            },
            {
              "name": "SCHEMA"
            },
            {
              "name": "SCALAR"
            },
            {
              "name": "OBJECT"
            },
            {
              "name": "FIELD_DEFINITION"
            },
            {
              "name": "ARGUMENT_DEFINITION"
            },
            {
              "name": "INTERFACE"
            },
            {
              "name": "UNION"
            },
            {
              "name": "ENUM"
            },
            {
              "name": "ENUM_VALUE"
            },
            {
              "name": "INPUT_OBJECT"
            },
            {
              "name": "INPUT_FIELD_DEFINITION"
            }
          ]
        },
        {
          "kind": "ENUM",
          "name": "CacheControlScope",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": [
            {
              "name": "PUBLIC"
            },
            {
              "name": "PRIVATE"
            }
          ]
        },
        {
          "kind": "SCALAR",
          "name": "Upload",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        }
      ]
    }
}
]]
