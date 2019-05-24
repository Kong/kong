local cjson = require "cjson"
local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"


local unindent = helpers.unindent


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


local MOCK_SERIALIZER = [[
return {
  serialize = function(ngx)
    return ngx
  end
}
]]
local MOCK_BAD_SERIALIZER = [[
return {
  nope = function(ngx)
    return ngx
  end
}
]]


for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy, function()
    local client

    lazy_setup(function()
      assert(helpers.start_kong({
        database = strategy,
      }))  
    end) 

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end) 

    before_each(function()
      client = assert(helpers.admin_client())
    end) 

    after_each(function()
      if client then 
        client:close()
      end
    end)

    describe("/log_serializers", function()
      describe("POST", function()
        local i = 0
        it_content_types("create a serializer", function(content_type)
          return function()
            i = i + 1

            local res = client:post("/log_serializers", {
              body = {
                name = "foo" .. i,
                chunk = ngx.encode_base64(MOCK_SERIALIZER),
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.equals("foo" .. i, json.name)
            assert.equals(ngx.encode_base64(MOCK_SERIALIZER), json.chunk)
            assert.True(utils.is_valid_uuid(json.id))
          end
        end)
      end)

      describe("errors", function()
        it_content_types("fails when given an unencoded chunk", function(content_type)
          return function()
            local res = client:post("/log_serializers", {
              body = {
                name = "bar",
                chunk = "im a giraffe",
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.SCHEMA_VIOLATION,
              name    = "schema violation",
              message = unindent([[
                schema violation
                (could not decode serializer chunk)
              ]], true, true),
              fields = {
                ["@entity"] = {
                  "could not decode serializer chunk"
                }
              }
            }, cjson.decode(body))
          end
        end)

        it_content_types("fails when given a chunk without 'serialize'", function(content_type)
          return function()
            local res = client:post("/log_serializers", {
              body = {
                name = "bar",
                chunk = ngx.encode_base64(MOCK_BAD_SERIALIZER),
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.SCHEMA_VIOLATION,
              name    = "schema violation",
              message = unindent([[
                schema violation
                (loaded serializer does not contain a public 'serialize' function)
              ]], true, true),
              fields = {
                ["@entity"] = {
                  "loaded serializer does not contain a public 'serialize' function"
                }
              }
            }, cjson.decode(body))
          end
        end)
      end)
    end)

  end)
end
