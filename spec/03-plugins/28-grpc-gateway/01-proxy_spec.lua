local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "]", function()
    local proxy_client
    local service1
    local route1
    local plugin1
    local bp

    lazy_setup(function()
      assert(helpers.start_grpc_target())

      -- start_grpc_target takes long time, the db socket might already
      -- be timeout, so we close it to avoid `db:init_connector` failing
      -- in `helpers.get_db_utils`
      helpers.db:connect()
      helpers.db:close()

      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-gateway",
      })

      -- the sample server we used is from
      -- https://github.com/grpc/grpc-go/tree/master/examples/features/reflection
      -- which listens 50051 by default
      service1 = assert(bp.services:insert {
        name = "grpc",
        protocol = "grpc",
        host = "127.0.0.1",
        port = helpers.get_grpc_target_port(),
      })

      route1 = assert(bp.routes:insert {
        protocols = { "http", "https" },
        paths = { "/" },
        service = service1,
      })

      local route2 = assert(bp.routes:insert {
        protocols = { "http", "https" },
        paths = { "/" },
        hosts = {"grpc-rest-test2.com"},
        service = service1,
      })

      plugin1 = assert(bp.plugins:insert {
        route = route1,
        name = "grpc-gateway",
        config = {
          proto = "./spec/fixtures/grpc/targetservice.proto",
          use_proto_names = true,
          emit_defaults = false,
        },
      })

      assert(bp.plugins:insert {
        route = route2,
        name = "grpc-gateway",
        config = {
          proto = "./spec/fixtures/grpc/targetservice.proto",
          use_proto_names = false,
          enum_as_name=false,
          emit_defaults = false,
        },
      })

      print ("Updating grpc-gateway plugin (id = " .. plugin1.id .. ") settings: use_proto_names=true; enum_as_name=false; emit_defaults=true")

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

    test("main entrypoint", function()
      local res, err = proxy_client:get("/v1/messages/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local body = res:read_body()
      local data = cjson.decode(body)

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    test("additional binding", function()
      local res, err = proxy_client:get("/v1/messages/legacy/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local data = cjson.decode((res:read_body()))

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    test("removes unbound query args", function()
      local res, err = proxy_client:get("/v1/messages/john_doe?arg1=1&arg2.test=2")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local body = res:read_body()
      local data = cjson.decode(body)

      assert.same({reply = "hello john_doe", boolean_test = false}, data)
    end)

    describe("boolean behavior", function ()
      test("true", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=true")
        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)
        assert.same({reply = "hello john_doe", boolean_test = true}, data)
      end)

      test("false", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=false")

        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = false}, data)
      end)

      test("zero", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=0")

        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = false}, data)
      end)

      test("non-zero", function()
        local res, err = proxy_client:get("/v1/messages/legacy/john_doe?boolean_test=1")
        assert.equal(200, res.status)
        assert.is_nil(err)

        local body = res:read_body()
        local data = cjson.decode(body)

        assert.same({reply = "hello john_doe", boolean_test = true}, data)
      end)
    end)

    test("unknown path", function()
      local res, _ = proxy_client:get("/v1/messages/john_doe/bai")
      assert.equal(400, res.status)
      assert.equal("Bad Request", res.reason)
    end)

    test("transforms grpc-status to HTTP status code", function()
      local res, _ = proxy_client:get("/v1/unknown/john_doe")
      -- per ttps://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto
      -- grpc-status: 12: UNIMPLEMENTED are mapped to http code 500
      assert.equal(500, res.status)
      assert.equal('12', res.headers['grpc-status'])
    end)

    test("structured URI args", function()
      local res, _ = proxy_client:get("/v1/grow/tail", {
        query = {
          name = "lizard",
          hands = { count = 0, endings = "fingers" },
          legs = { count = 4, endings = "toes" },
          tail = { count = 0, endings = "tip" },
        }
      })
      assert.equal(200, res.status)
      local body = assert(res:read_body())
      assert.same({
        name = "lizard",
        hands = { count = 0, endings = "fingers" },
        legs = { count = 4, endings = "toes" },
        tail = {count = 1, endings = "tip" },
      }, cjson.decode(body))
    end)

    describe("grpc <-> json transformations", function()
      local decimal_positive = 10.5
      local decimal_negative = -3.75
      local int32_positive = 11
      local int64_positive = 2305843009213693951 -- 4611686018427387903 flips the sign?
      local int32_negative = -15
      local int64_negative = -2305843009213693951 -- for some reason 2^62 is the maximum negative value

      local H = function( string )
        return "hello " .. ( string or "" )
      end

      -- lazy_setup(function()
      --   print ("Updating grpc-gateway plugin (id = " .. plugin1.id .. ") settings: use_proto_names=false; enum_as_name=true; emit_defaults=false")

      --   assert(bp.plugins:update( { id = plugin1.id }, {
      --     config = {
      --       proto = "./spec/fixtures/grpc/targetservice.proto",
      --       use_proto_names = false,
      --       enum_as_name = true,
      --       emit_defaults = false,
      --     },
      --   } ))
 
      --   assert(helpers.restart_kong {
      --     database = strategy,
      --     plugins = "bundled,grpc-gateway",
      --   })
      -- end)

      describe("scalar types", function()
        it("completely filled request", function()
          local request = {
            doubleVal = decimal_positive,
            doubleVals = { decimal_negative, decimal_positive },
            floatVal = decimal_negative,
            floatVals = { decimal_positive, decimal_negative },
            int64Val = tostring( int64_negative ),
            int64Vals = { tostring( int64_positive ), tostring( int64_negative ) },
            uint64Val = tostring( int64_positive ),
            uint64Vals = { tostring( int64_positive ), tostring( int64_positive+1 ) },
            sint64Val = tostring( int64_negative ),
            sint64Vals = { tostring( int64_negative ), tostring( int64_positive ) },
            fixed64Val = tostring( int64_positive ),
            fixed64Vals = { tostring( int64_positive ), tostring( int64_positive+1 ) },
            sfixed64Val = tostring( int64_negative ),
            sfixed64Vals = { tostring( int64_negative ), tostring( int64_positive ) },
            int32Val = int32_negative,
            int32Vals = { int32_negative, int32_positive },
            uint32Val = int32_positive,
            uint32Vals = { int32_positive, int32_positive+1 },
            sint32Val = int32_negative, 
            sint32Vals = { int32_negative, int32_positive },
            fixed32Val = int32_positive,
            fixed32Vals = { int32_positive, int32_positive+1 },
            sfixed32Val = int32_negative,
            sfixed32Vals = { int32_negative, int32_positive },
            boolVal = false,
            boolVals = { true, false, true },
            bytesVal = "aSBsb3ZlIGtvbmc=", -- "i love kong"
            bytesVals = { "dW5pdA==", "dGVzdA=="}, -- "unit", "test"
            stringVal = "kong",
            stringVals = { "grpc", "gateway" }
          }

          local res, _ = proxy_client:post("/bounceScalars", {
            headers = { ["Content-Type"] = "application/json" },
            body = request
          })
  
          assert.equal(200, res.status)  
          local response = res:read_body()
  
          assert.same({
            doubleVal = decimal_positive*2,
            doubleVals = { decimal_negative*2, decimal_positive*2 },
            floatVal = decimal_negative*2,
            floatVals = { decimal_positive*2, decimal_negative*2 },
            int64Val = tostring( int64_negative*2 ),
            int64Vals = { tostring( int64_positive*2 ), tostring( int64_negative*2 ) },
            uint64Val = tostring( int64_positive*2 ),
            uint64Vals = { tostring( int64_positive*2 ), tostring( (int64_positive+1)*2 ) },
            sint64Val = tostring( int64_negative*2 ),
            sint64Vals = { tostring( int64_negative*2 ), tostring( int64_positive*2 ) },
            fixed64Val = tostring( int64_positive*2 ),
            fixed64Vals = { tostring( int64_positive*2 ), tostring( (int64_positive+1)*2 ) },
            sfixed64Val = tostring( int64_negative*2 ),
            sfixed64Vals = { tostring( int64_negative*2 ), tostring( int64_positive*2 ) },
            int32Val = int32_negative*2,
            int32Vals = { int32_negative*2, int32_positive*2 },
            uint32Val = int32_positive*2,
            uint32Vals = { int32_positive*2, (int32_positive+1)*2 },
            sint32Val = int32_negative*2, 
            sint32Vals = { int32_negative*2, int32_positive*2 },
            fixed32Val = int32_positive*2,
            fixed32Vals = { int32_positive*2, (int32_positive+1)*2 },
            sfixed32Val = int32_negative*2,
            sfixed32Vals = { int32_negative*2, int32_positive*2 },
            boolVal = true,
            boolVals = {false,true,false},
            bytesVal = "aSBsb3ZlIGtvbmcgYWJj", -- "i love kong abc"
            bytesVals = {"dW5pdCBhYmM=","dGVzdCBhYmM="}, -- "unit abc", "test abc"
            stringVal = "hello kong",
            stringVals = {"hello grpc","hello gateway"},
          }, cjson.decode(response))
        end)
  
        it("empty request", function()
          local res, _ = proxy_client:post("/bounceScalars", {
            headers = { ["Content-Type"] = "application/json", ["Host"] = "grpc-rest-test2.com" },
            body = {},
          })
  
          assert.equal(200, res.status)
  
          local body = res:read_body()
  
          assert.same({
            bytesVal = "IGFiYw==", -- abc
            stringVal = "hello ",
            boolVal = true
          }, cjson.decode(body))
        end) 
      end)
      
      describe("wrappers types", function()
        it("all filled", function()
          local request = {
            doubleWrapper = decimal_positive,
            doubleWrappers = { decimal_negative, decimal_positive },
            floatWrapper = decimal_negative,
            floatWrappers = { decimal_positive, decimal_negative },
            int64Wrapper = tostring( int32_negative ),
            int64Wrappers = { tostring( int32_positive ), tostring( int32_negative ) },
            uint64Wrapper = tostring( int32_positive),
            uint64Wrappers = { tostring( int32_positive ), tostring( int32_positive ) },
            int32Wrapper = int32_negative,
            int32Wrappers = { int32_negative, int32_positive },
            uint32Wrapper = int32_positive,
            uint32Wrappers = { int32_positive, int32_positive },
            boolWrapper = true,
            boolWrappers = { false, true, false },
            stringWrapper = "grpc-gateway",
            stringWrappers = { "grpc", "gateway" },
            bytesWrapper = "aSBsb3ZlIGtvbmc=", -- "i love kong"
            bytesWrappers = { "dW5pdA==", "dGVzdA=="}, -- "unit", "test"
          }

          local res, _ = proxy_client:post("/bounceWrappers", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)

          local body = res:read_body()

          assert.same({
            doubleWrapper = decimal_positive*2,
            doubleWrappers = { decimal_negative*2, decimal_positive*2 },
            floatWrapper = decimal_negative*2,
            floatWrappers = { decimal_positive*2, decimal_negative*2 },
            int64Wrapper = tostring( int32_negative*2 ),
            int64Wrappers = { tostring( int32_positive*2 ), tostring( int32_negative*2 ) },
            uint64Wrapper = tostring( int32_positive*2),
            uint64Wrappers = { tostring( int32_positive*2 ), tostring( int32_positive*2 ) },
            int32Wrapper = int32_negative*2,
            int32Wrappers = { int32_negative*2, int32_positive*2 },
            uint32Wrapper = int32_positive*2,
            uint32Wrappers = { int32_positive*2, int32_positive*2 },
            boolWrapper = false,
            boolWrappers = {true, false, true},
            bytesWrapper = "aSBsb3ZlIGtvbmcgYWJj", -- "i love kong abc"
            bytesWrappers = {"dW5pdCBhYmM=","dGVzdCBhYmM="}, -- "unit abc", "test abc"
            stringWrapper = "hello grpc-gateway",
            stringWrappers = {"hello grpc","hello gateway"},            
          }, cjson.decode(body))
        end)

        it("Wrappers (none filled)", function()
          local res, _ = proxy_client:post("/bounceWrappers", {
            headers = { ["Content-Type"] = "application/json" },
            body = {},
          })

          assert.equal(200, res.status)
          
          local body = res:read_body()

          assert.same({
            doubleWrapper = 0,
            floatWrapper= 0,
            int64Wrapper = "0",
            uint64Wrapper = "0",
            int32Wrapper = 0,
            uint32Wrapper = 0,
            boolWrapper = true,
            bytesWrapper = "IGFiYw==",
            stringWrapper = "hello ",
          }, cjson.decode(body))
        end)

        -- filled with defaults to check fields of default values
      end)

      describe("date-time types", function()
        local date = require "date"

        local format_time = function( d )
          local res = d:fmt( "%Y-%m-%dT%H:%M:%\f" )
          -- remove trailing zeroes as in https://github.com/golang/protobuf/blob/v1.5.2/jsonpb/encode.go#L204
          res = res:gsub("000$", "" )
          res = res:gsub("000$", "" )
          res = res:gsub(".000$", "" )
      
          return res.."Z"
        end
      
        local get_times = function( utc_offset, time_distance, postponement )
          local sign, utc_hrs, utc_min = string.match( utc_offset, "(-?)(%d+):(%d+)")

          sign = 2*#(sign or "") * (-1) +1

          local seconds = sign*tonumber(utc_hrs)*3600 + sign*tonumber(utc_min)*60

          local now = date()
          local now_utc = now:fmt( "${iso}Z" )
          local now_local = now:addseconds( seconds ):fmt( "${iso}"..utc_offset )

          local when = now:addseconds( time_distance )
          local when_utc = format_time( when )
          local new_when_utc = format_time( when:addseconds( postponement ) )

          if utc_offset:find("00:00") then now_local = now_utc  end

          seconds = seconds + time_distance + postponement

          local request = { now = now_local, when = when_utc, postponement = tostring(postponement).."s" }
          local response = { now = now_utc, newWhen = new_when_utc, totalDelay = seconds.."s" }

          return request, response
        end

        it("zulu timestamps +10s apart, one shifted by 20s duration", function()
          local request, expected_response = get_times( "00:00", 10, 20 )

          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)
          assert.same( expected_response, cjson.decode( (res:read_body()) ))
        end)

        it("zulu timestamps -10s apart, one shifted by +20s duration", function()
          local request, expected_response = get_times( "00:00", -10, 20 )

          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)  
          assert.same( expected_response, cjson.decode( (res:read_body()) ))
        end)

        it("zulu timestamps +10s apart, one shifted by +20.25s duration", function()
          local request, expected_response = get_times( "00:00", 10, 20.25 )

          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)  
          assert.same( expected_response, cjson.decode( (res:read_body()) ))
        end)

        it("timestamps -10s apart, one zulu, one UCT-00:01, one shifted by 20.25s duration", function()
          local request, expected_response = get_times( "-00:01", -10, 20.25 )

          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)  
          assert.same( expected_response, cjson.decode( (res:read_body()) ))
        end)

        it("timestamps -10.75s apart, one zulu, one UCT-00:01, one shifted by 20.25s duration", function()
          local request, expected_response = get_times( "-00:01", -10.75, 20.25 )
    
          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = request,
          })

          assert.equal(200, res.status)  
          assert.same( expected_response, cjson.decode( (res:read_body()) ))
        end)

        it("timestamps empty request", function()
          local res, _ = proxy_client:post("/bounceGoodTimes", {
            headers = { ["Content-Type"] = "application/json" },
            body = {},
          })

          assert.equal(200, res.status)
          assert.same({
            newWhen = '1970-01-01T00:00:00Z',
            now = '1970-01-01T00:00:00Z',
            totalDelay = '0s',
          }, cjson.decode( (res:read_body()) ))
        end)
      end)

      describe("struct types", function()
        it("Struct (filled)", function()
          local res, _ = proxy_client:post("/bounceStruct", {
            headers = { ["Content-Type"] = "application/json" },
            body = {
              test = {
                  name = { "grpc", "gateway" },
                  versions = { int32_positive, int32_negative },
                  id = nil
                },
                number = decimal_negative,
                tested = true
            }
          })

          assert.equal(200, res.status)
          assert.same({
            test = {
              name = { "hello grpc", "hello gateway" },
              versions = { int32_positive*2, int32_negative*2 },
            },
            number = decimal_negative * 2,
            tested = false
          }, cjson.decode( (res:read_body()) ))
        end)

        pending( "empty struct" ) 
      end)
  
      it("enum_as_name = true", function()
        local request = { 
          complexValue = {
            any = {
              ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              enumVal = 0,
              repeatedComplex = {
                { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1 } },
                { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2 } }
              },
              any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType",
                enumVal = 0,
                singularComplex = {
                  intMap = {
                    ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1 } },
                  },
                  stringMap = {
                    ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2 } },
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
          complexValue = {
            anyProcessed = true, boolVal = true,
            any = {
              ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              repeatedComplex = {
                { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = "FOO_COMPLEX_NAME", boolVal = true }, boolVal = true },
                { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = "FOO_ANOTHER_VALUE", boolVal = true }, boolVal = true }
              },
              anyProcessed = true, boolVal = true,
              any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", boolVal = true,
                singularComplex = {
                  boolVal = true,
                  intMap = {
                    ["200"] = { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = "FOO_COMPLEX_NAME", boolVal = true }, boolVal = true },
                  },
                  stringMap = {
                    ["200"] = { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = "FOO_ANOTHER_VALUE", boolVal = true }, boolVal = true },
                  }
                } 
              }
            }
          }
        }, cjson.decode( (res:read_body()) ))
      end)
  
      describe("use_proto_names = true emit_defaults = false", function()
        lazy_setup(function()
          print ("Updating grpc-gateway plugin (id = " .. plugin1.id .. ") settings: use_proto_names=true; enum_as_name=false; emit_defaults=false")

          assert(bp.plugins:update( { id = plugin1.id }, {
            config = {
              proto = "./spec/fixtures/grpc/targetservice.proto",
              use_proto_names = true,
              enum_as_name = false,
              emit_defaults = false,
            },
          } ))
   
          assert(helpers.restart_kong {
            database = strategy,
            plugins = "bundled,grpc-gateway",
          })
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
      -- use_proto_names = false

      -- enums with numbers
        -- with defaults
      -- enums with names
        -- with defaults

      -- populate default fields

      -- any + extra import (additional proto)
            
      -- non-string 64bit int fields
      -- maps with duplicate keys
      -- wrong bool
      -- wrong number
      -- wrong map key
    end)

    describe("enum_as_name = false", function()
      lazy_setup(function()
        print ("Updating grpc-gateway plugin (id = " .. plugin1.id .. ") settings: use_proto_names=false; enum_as_name=false; emit_defaults=false")

        assert(bp.plugins:update( { id = plugin1.id }, {
          config = {
            proto = "./spec/fixtures/grpc/targetservice.proto",
            use_proto_names = false,
            enum_as_name = false,
            emit_defaults = false,
          },
        } ))
 
        assert(helpers.restart_kong {
          database = strategy,
          plugins = "bundled,grpc-gateway",
        })
      end)

      it("emit_defaults = false", function()
        local request = { 
          complexValue = {
            any = {
              ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              enumVal = 0,
              repeatedComplex = {
                { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1 } },
                { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2 } }
              },
              any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType",
                enumVal = 0,
                singularComplex = {
                  intMap = {
                    ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1 } },
                  },
                  stringMap = {
                    ["200"] = { any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2 } },
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
          complexValue = {
            anyProcessed = true, boolVal = true,
            any = {
              ["@type"] = "type.googleapis.com/targetservice.ComplexType", 
              repeatedComplex = {
                { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1, boolVal = true }, boolVal = true },
                { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2, boolVal = true }, boolVal = true }
              },
              anyProcessed = true, boolVal = true,
              any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", boolVal = true,
                singularComplex = {
                  boolVal = true,
                  intMap = {
                    ["200"] = { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 1, boolVal = true }, boolVal = true },
                  },
                  stringMap = {
                    ["200"] = { anyProcessed = true, any = { ["@type"] = "type.googleapis.com/targetservice.ComplexType", enumVal = 2, boolVal = true }, boolVal = true },
                  }
                } 
              }
            }
          }
        }, cjson.decode( (res:read_body()) ))
      end)
    end)

    it("invalid bool value", function()
      local res, _ = proxy_client:post( "/bounceMaskedFields", {
        headers = { ["Content-Type"] = "application/json" },
        body = { complexValue = { bool_val = "untrue" } }
      })
      
      assert.equal(400, res.status)
      assert.equal("failed to encode payload", (res:read_body())) -- expected boolean value at .complexValue.bool_val, got: 'untrue' of type: string
    end)

    test("null in json", function()
      local res, _ = proxy_client:post("/bounce", {
        headers = { ["Content-Type"] = "application/json" },
        body = { message = cjson.null },
      })
      assert.equal(400, res.status)
    end)

    describe("regression", function()
      test("empty array in json #10801", function()
        local req_body = { array = {}, nullable = "ahaha" }
        local res, _ = proxy_client:post("/v1/echo", {
          headers = { ["Content-Type"] = "application/json" },
          body = req_body,
        })
        assert.equal(200, res.status)
  
        local body = res:read_body()
        assert.same(req_body, cjson.decode(body))
        -- it should be encoded as empty array in json instead of `null` or `{}`
        assert.matches("[]", body, nil, true)
      end)
  
      -- Bug found when test FTI-5002's fix. It will be fixed in another PR.
      test("empty message #10802", function()
        local req_body = { array = {}, nullable = "" }
        local res, _ = proxy_client:post("/v1/echo", {
          headers = { ["Content-Type"] = "application/json" },
          body = req_body,
        })
        assert.equal(200, res.status)
  
        local body = res:read_body()
        assert.same(req_body, cjson.decode(body))
        -- it should be encoded as empty array in json instead of `null` or `{}`
        assert.matches("[]", body, nil, true)
      end)
    end)
  end)
end
