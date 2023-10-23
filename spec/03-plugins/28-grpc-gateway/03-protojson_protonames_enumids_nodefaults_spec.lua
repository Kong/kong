local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "], settings: use_proto_names=true; enum_as_name=false; emit_defaults=false", function()
    local proxy_client
    
--    local decimal_positive = 10.5
--    local decimal_negative = -3.75
--    local int32_positive = 11
--    local int64_positive = 2305843009213693951 -- 4611686018427387903 flips the sign?
--    local int32_negative = -15
--    local int64_negative = -2305843009213693951 -- for some reason 2^62 is the maximum negative value

    local H = function( string )
      return "hello " .. ( string or "" )
    end

    lazy_setup(function()
      assert(helpers.start_grpc_target())

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-gateway",
      })

      -- the sample server we used is from
      -- https://github.com/grpc/grpc-go/tree/master/examples/features/reflection
      -- which listens 50051 by default
      local service1 = assert(bp.services:insert {
        name = "grpc",
        protocol = "grpc",
        host = "127.0.0.1",
        port = helpers.get_grpc_target_port(),
      })

      local route1 = assert(bp.routes:insert {
        protocols = { "http", "https" },
        paths = { "/" },
        service = service1,
      })

      assert(bp.plugins:insert {
        route = route1,
        name = "grpc-gateway",
        config = {
          proto = "./spec/fixtures/grpc/targetservice.proto",
          use_proto_names = true,
          enum_as_name = false,
          emit_defaults = false,
        },
      })

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,grpc-gateway",
      })
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(1000)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.stop_grpc_target()
    end)
   
    it("nested messages: snake_case -> snake_case", function()
      local request = { 
        complex_value = {                
          string_val = "snake_case.snake_case",
          complex_value = {
            string_val = "snake_case.snake_case.snake_case",
            complex_values = {
              { string_val = "snake_case.snake_case.snake_case.1.snake_case" },
              { string_val = "snake_case.snake_case.snake_case.2.snake_case" }
            },
          },
        },
      }

      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          string_val = H(request.complex_value.string_val), bool_val = true,

          complex_value = {
            string_val = H(request.complex_value.complex_value.string_val), bool_val = true,

            complex_values = {
              { string_val = H(request.complex_value.complex_value.complex_values[1].string_val), bool_val = true },
              { string_val = H(request.complex_value.complex_value.complex_values[2].string_val), bool_val = true }
            },
          },
        }, 
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested messages: jsonName/camelCase -> snake_case", function()
      local request = { 
        complexValue = {                
          stringVal = "camelCase.camelCase",
          singularComplex = {
            stringVal = "camelCase.jsonName.camelCase",
            repeatedComplex = {
              { stringVal = "camelCase.jsonName.jsonName.1.camelCase" },
              { stringVal = "camelCase.jsonName.jsonName.1.camelCase" }
            },
          },
        },
      }

      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status) 
      assert.same({
        complex_value = {
          string_val = H(request.complexValue.stringVal), bool_val = true,

          complex_value = {
            string_val = H(request.complexValue.singularComplex.stringVal), bool_val = true,

            complex_values = {
              { string_val = H(request.complexValue.singularComplex.repeatedComplex[1].stringVal), bool_val = true },
              { string_val = H(request.complexValue.singularComplex.repeatedComplex[2].stringVal), bool_val = true }
            },
          },
        }, 
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested messages: undefined jsonName  -> snake_case", function()
      local request = { 
        complexValue = {                
          string_val = "camelCase.snake_case",

          complexValue = {
            stringVal = "camelCase.undefinedJsonName.camelCase - should not be processed",

            complexValues = {
              { string_val = "camelCase.undefinedJsonName.undefinedJsonName.1.snake_case - should not be processed" },
              { stringVal = "camelCase.undefinedJsonName.undefinedJsonName.2.snake_case - should not be processed" }
            },
          },
        },
      }

      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          string_val = H(request.complexValue.string_val), bool_val = true,
        }, 
      }, cjson.decode( (res:read_body()) ))          
    end)

    it("nested maps: snake_case -> snake_case", function()
      local request = { 
        complex_value = {                
          int_map = {
            ["3"] = { string_val = "snake_case.snake_case.3 - integer map",
              complex_values = {
                { string_val = "snake_case.snake_case.3.snake_case.snake_case - integer map, nested repeated complex" },
                { string_val = "snake_case.snake_case.3.snake_case.snake_case - integer map, nested repeated complex" }
              }
            },
            ["7"] = { string_val = "snake_case.snake_case.7 - integer_map",
                      string_map = {
                        a = { string_val = "snake_case.snake_case.7.snake_case.a.snake_case - nested string map" },
                        b = { string_val = "snake_case.snake_case.7.snake_case.b.snake_case - nested string map" }
                      },
            },
          },
          string_map = {
            kong = { string_val = "snake_case.snake_case.kong.snake_case - string map, simple key",
                     int_map = {
                       ["2"] = { string_val = "snake_case.snake_case.kong.snake_case.2.snake_case - nested int map" },
                       ["100"]= { string_val = "snake_case.snake_case.kong.snake_case.100.snake_case - nested int map" },
                     },
            },
            ["grpc.gateway"] = {
              complex_value = { string_val = "snake_case.snake_case.'grpc.gateway'.snake_case.snake_case - string map, complex key" },
            },
          },
        },
      }

      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          bool_val = true,
          int_map = {
            ["3"] = { string_val = H(request.complex_value.int_map["3"].string_val), bool_val = true,
              complex_values = {
                { string_val = H(request.complex_value.int_map["3"].complex_values[1].string_val), bool_val = true },
                { string_val = H(request.complex_value.int_map["3"].complex_values[2].string_val), bool_val = true }
              }
            },
            ["7"] = { string_val = H(request.complex_value.int_map["7"].string_val), bool_val = true,
                      string_map = {
                        a = { string_val = H(request.complex_value.int_map["7"].string_map.a.string_val), bool_val = true },
                        b = { string_val = H(request.complex_value.int_map["7"].string_map.b.string_val), bool_val = true }
                      },
            },
          },
          string_map = {
            kong = { string_val = H(request.complex_value.string_map["kong"].string_val), bool_val = true,
                     int_map = {
                       ["2"] = { string_val = H(request.complex_value.string_map["kong"].int_map["2"].string_val), bool_val = true },
                       ["100"]= { string_val = H(request.complex_value.string_map["kong"].int_map["100"].string_val), bool_val = true },
                     },
            },
            ["grpc.gateway"] = {
              bool_val = true,
              complex_value = { string_val = H(request.complex_value.string_map["grpc.gateway"].complex_value.string_val), bool_val = true },
            },
          },
        },
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested maps: jsonName/camelCase -> snake_case", function()
      local request = { 
        complexValue = {                
          intMap = {
            ["3"] = { stringVal = "camelCase.camelCase.3.camelCase - integer map",
                      repeatedComplex = {
                        { stringVal = "camelCase.camelCase.3.jsonName.camelCase - integer map, nested jsonName" },
                        { stringVal = "camelCase.camelCase.3.jsonName.camelCase - integer map, nested jsonName" }
                      }
            },
            ["7"] = { stringVal = "camelCase.camelCase.7.camelCase - integer_map",
                      stringMap = {
                        a = { stringVal = "camelCase.camelCase.7.camelCase.a.camelCase - nested string map" },
                        b = { stringVal = "camelCase.camelCase.7.camelCase.b.camelCase - nested string map" }
                      },
            },
          },
          stringMap = {
            kong = { stringVal = "camelCase.camelCase.kong.camelCase - string map, simple key",
                     intMap = {
                       ["2"] = { stringVal = "camelCase.camelCase.kong.camelCase.2.camelCase - nested int map" },
                       ["100"]= { stringVal = "camelCase.camelCase.kong.camelCase.100.camelCase - nested int map" },
                     },
            },
            ["grpc.gateway"] = {
              singularComplex = { stringVal = "camelCase.camelCase.'grpc.gateway'.jsonName.camelCase - string map, complex key" },
            },
          },
        },
      }

      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          bool_val = true,
          int_map = {
            ["3"] = { string_val = H(request.complexValue.intMap["3"].stringVal), bool_val = true,
              complex_values = {
                { string_val = H(request.complexValue.intMap["3"].repeatedComplex[1].stringVal), bool_val = true },
                { string_val = H(request.complexValue.intMap["3"].repeatedComplex[2].stringVal), bool_val = true }
              }
            },
            ["7"] = { string_val = H(request.complexValue.intMap["7"].stringVal), bool_val = true,
                      string_map = {
                        a = { string_val = H(request.complexValue.intMap["7"].stringMap.a.stringVal), bool_val = true },
                        b = { string_val = H(request.complexValue.intMap["7"].stringMap.b.stringVal), bool_val = true }
                      },
            },
          },
          string_map = {
            kong = { string_val = H(request.complexValue.stringMap["kong"].stringVal), bool_val = true,
                     int_map = {
                       ["2"] = { string_val = H(request.complexValue.stringMap["kong"].intMap["2"].stringVal), bool_val = true },
                       ["100"]= { string_val = H(request.complexValue.stringMap["kong"].intMap["100"].stringVal), bool_val = true },
                     },
            },
            ["grpc.gateway"] = {
              bool_val = true,
              complex_value = { string_val = H(request.complexValue.stringMap["grpc.gateway"].singularComplex.stringVal), bool_val = true },
            },
          },
        },
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested maps: undefined jsonName -> snake_case", function()
      local request = { 
        complexValue = {
          intMap = {
            ["7"] = { string_map = {
                        a = { complexValue = { string_val = "camelCase.camelCase.7.snake_case.a.jsonName.snake_case - nested string map" } },
                        b = { complexValues = {
                               { string_val = "camelCase.camelCase.7.snake_case.b.undefinedJsonName.snake_case - should not be processed" },
                               { stringVal = "camelCase.camelCase.7.snake_case.b.undefinedJsonName.camelCase - should not be processed" }
                        }}
                    }}
          },
          stringMap = {
            kong = { 
              int_map = { ["2"] = { complexValues = {
                                      { string_val = "camelCase.camelCase.kong.snake_case.2.jsonName.snake_case - should not be processed" },
                                      { stringVal = "camelCase.camelCase.kong.snake_case.2.jsonName.camelCase - should not be processed" }
                                  }}
            }},
            ["grpc.gateway"] = {
              complexValue = { string_val = "camelCase.camelCase.'grpc.gateway'.undefinedJsonName.snake_case - should not be processed" },
            },
          },
        },
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          bool_val = true,
          int_map = {
            ["7"] = { bool_val = true,
                      string_map = {
                        a = { bool_val = true },
                        b = { bool_val = true }
                      },
            },
          },
          string_map = {
            kong = { int_map = { ["2"] = { bool_val = true } }, bool_val = true },
            ["grpc.gateway"] = { bool_val = true },
          },
        },
      }, cjson.decode( (res:read_body()) ))
    end)

    it("fieldmask: snake_case -> snake_case", function()
      local request = { 
        complex_value = {
          complex_value = {
            field_mask = "complex_value.enum_val,complex_value.int_map,complex_value.any",
            complex_values = {
              { field_mask = "complex_value.complex_value.int64_val,complex_values" },
              { field_mask = "complex_value.complex_values" }
            }
          },
          field_mask = "complex_value.complex_value.int64_val"
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          complex_value = {
            field_mask = "complex_value.enum_val,complex_value.int_map,complex_value.any,complex_value.field_mask", bool_val = true,
            complex_values = {
              { field_mask = "complex_value.complex_value.int64_val,complex_values,complex_value.field_mask", bool_val = true },
              { field_mask = "complex_value.complex_values,complex_value.field_mask", bool_val = true }
            }
          },
          field_mask = "complex_value.complex_value.int64_val,complex_value.field_mask", bool_val = true
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("fieldmask: camelCase -> snake_case", function()
      local request = { 
        complexValue = {
          singularComplex = {
            fieldMask = "complexValue.enumVal,complexValue.intMap,complexValue.any",
            repeatedComplex = {
              { fieldMask = "complexValue.complexValue.int64Val,complexValues" },
              { fieldMask = "complexValue.complexValues" }
            }
          },
          fieldMask = "complexValue.complexValue.int64Val"
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          complex_value = {
            field_mask = "complex_value.enum_val,complex_value.int_map,complex_value.any,complex_value.field_mask", bool_val = true,
            complex_values = {
              { field_mask = "complex_value.complex_value.int64_val,complex_values,complex_value.field_mask", bool_val = true },
              { field_mask = "complex_value.complex_values,complex_value.field_mask", bool_val = true }
            }
          },
          field_mask = "complex_value.complex_value.int64_val,complex_value.field_mask", bool_val = true
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("fieldmask: mixed_Case -> snake_case", function()
      local request = { 
        complexValue = {
          singularComplex = {
            fieldMask = "complex_value.enumVal,complexValue.int_map,complexValue.any",
            repeatedComplex = {
              { fieldMask = "complexValue.complex_value.int64Val,complex_values" },
              { fieldMask = "complexValue.complexValues" }
            }
          },
          fieldMask = "complexValue.complexValue.int64Val"
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          complex_value = {
            field_mask = "complex_value.enum_val,complex_value.int_map,complex_value.any,complex_value.field_mask", bool_val = true,
            complex_values = {
              { field_mask = "complex_value.complex_value.int64_val,complex_values,complex_value.field_mask", bool_val = true },
              { field_mask = "complex_value.complex_values,complex_value.field_mask", bool_val = true }
            }
          },
          field_mask = "complex_value.complex_value.int64_val,complex_value.field_mask", bool_val = true
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("fieldmask: jsonName (invalid)", function()
      local request = { 
        complexValue = {
          singularComplex = {
            fieldMask = "singularComplex.enumVal,complexValue.int_map,singularComplex.any",
            repeatedComplex = {
              { fieldMask = "singularComplex.singularComplex.intVal,repeatedComplex" },
              { fieldMask = "singularComplex.repeatedComplex,invalidPath,complex_VALUE" }
            }
          },
          fieldMask = "singularComplex.complexValue.int64Val,any.int64Val,intMap.3"
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          complex_value = {
            field_mask = "complex_value.field_mask", bool_val = true,
            complex_values = {
              { field_mask = "complex_value.field_mask", bool_val = true },
              { field_mask = "complex_value.field_mask", bool_val = true }
            }
          },
          field_mask = "complex_value.field_mask", bool_val = true
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("fieldmask: mixed_Case -> snake_case", function()
      local request = { 
        complexValue = {
          singularComplex = {
            fieldMask = "complex_value.enumVal,complexValue.int_map,complexValue.any",
            repeatedComplex = {
              { fieldMask = "complexValue.complex_value.int64Val,complex_values" },
              { fieldMask = "complexValue.complexValues" }
            }
          },
          fieldMask = "complexValue.complexValue.int64Val"
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          complex_value = {
            field_mask = "complex_value.enum_val,complex_value.int_map,complex_value.any,complex_value.field_mask", bool_val = true,
            complex_values = {
              { field_mask = "complex_value.complex_value.int64_val,complex_values,complex_value.field_mask", bool_val = true },
              { field_mask = "complex_value.complex_values,complex_value.field_mask", bool_val = true }
            }
          },
          field_mask = "complex_value.complex_value.int64_val,complex_value.field_mask", bool_val = true
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested any: snake_case -> snake_case", function()
      local request = { 
        complex_value = {
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
            complex_values = {
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = "nested repeated" } },
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = "nested repeated" } }
            },
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              complex_value = {
                int_map = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = "nested int_map" } },
                },
                string_map = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = "nested string_map" } },
                }
              } 
            }
          }
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          any_processed = true, bool_val = true,
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
            complex_values = {
              { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested repeated"), bool_val = true }, bool_val = true },
              { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested repeated"), bool_val = true }, bool_val = true }
            },
            any_processed = true, bool_val = true,
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", bool_val = true,
              complex_value = {
                bool_val = true,
                int_map = {
                  ["200"] = { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested int_map"), bool_val = true }, bool_val = true },
                },
                string_map = {
                  ["200"] = { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested string_map"), bool_val = true }, bool_val = true },
                }
              } 
            }
          }
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested any: jsonName/camelCase -> snake_case", function()
      local request = { 
        complexValue = {
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
            repeatedComplex = {
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "nested repeated" } },
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "nested repeated" } }
            },
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              singularComplex = {
                intMap = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "nested int_map" } },
                },
                stringMap = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "nested string_map" } },
                }
              }
            }
          }
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)  
      assert.same({
        complex_value = {
          any_processed = true, bool_val = true,
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
            complex_values = {
              { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested repeated"), bool_val = true }, bool_val = true },
              { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested repeated"), bool_val = true }, bool_val = true }
            },
            any_processed = true, bool_val = true,
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", bool_val = true,
              complex_value = {
                bool_val = true,
                int_map = {
                  ["200"] = { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested int_map"), bool_val = true }, bool_val = true },
                },
                string_map = {
                  ["200"] = { any_processed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", string_val = H("nested string_map"), bool_val = true }, bool_val = true },
                }
              } 
            }
          }
        }
      }, cjson.decode( (res:read_body()) ))
    end)

    it("nested any: jsonName (invalid)", function()
      local request = { 
        complexValue = {
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
            complexValues = {
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "should not be processed" } },
              { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "should not be processed" } }
            },
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              complexValue = {
                intMap = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "should not be processed" } },
                },
                stringMap = {
                  ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", stringVal = "should not be processed" } },
                }
              }
            }
          }
        }
      }
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = request
      })

      assert.equal(200, res.status)
      assert.same({
        complex_value = {
          any_processed = true, bool_val = true,
          any = {
            ["@type"] = "type.googleapis.com/targetservice.ComplexType",
            any_processed = true, bool_val = true,
            any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", bool_val = true }
          }
        }
      }, cjson.decode( (res:read_body()) ))
    end)
  end)
end
