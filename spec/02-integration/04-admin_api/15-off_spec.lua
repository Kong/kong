local cjson   = require "cjson"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end

describe("Admin API #off", function()
  local client

  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
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

  describe("/routes", function()
    describe("POST", function()
      it_content_types("doesn't allow to creates a route", function(content_type)
        return function()
          if content_type == "multipart/form-data" then
            -- the client doesn't play well with this
            return
          end

          local res = client:post("/routes", {
            body = {
              protocols = { "http" },
              hosts     = { "my.route.com" },
              service   = { id = utils.uuid() },
            },
            headers = { ["Content-Type"] = content_type }
          })
          local body = assert.res_status(405, res)
          local json = cjson.decode(body)
          assert.same({
            code    = Errors.codes.OPERATION_UNSUPPORTED,
            name    = Errors.names[Errors.codes.OPERATION_UNSUPPORTED],
            message = "cannot create 'routes' entities when not using a database",
          }, json)
        end
      end)

      it_content_types("doesn't allow to creates a complex route", function(content_type)
        return function()
          if content_type == "multipart/form-data" then
            -- the client doesn't play well with this
            return
          end

          local res = client:post("/routes", {
            body    = {
              protocols = { "http" },
              methods   = { "GET", "POST", "PATCH" },
              hosts     = { "foo.api.com", "bar.api.com" },
              paths     = { "/foo", "/bar" },
              service   = { id =  utils.uuid() },
            },
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(405, res)
          local json = cjson.decode(body)
          assert.same({
            code    = Errors.codes.OPERATION_UNSUPPORTED,
            name    = Errors.names[Errors.codes.OPERATION_UNSUPPORTED],
            message = "cannot create 'routes' entities when not using a database",
          }, json)
        end
      end)
    end)

    describe("GET", function()
      describe("errors", function()
        it("handles invalid offsets", function()
          local res  = client:get("/routes", { query = { offset = "x" } })
          local body = assert.res_status(400, res)
          assert.same({
            code    = Errors.codes.INVALID_OFFSET,
            name    = "invalid offset",
            message = "'x' is not a valid offset: bad base64 encoding"
          }, cjson.decode(body))

          res  = client:get("/routes", { query = { offset = "|potato|" } })
          body = assert.res_status(400, res)

          local json = cjson.decode(body)
          json.message = nil

          assert.same({
            code = Errors.codes.INVALID_OFFSET,
            name = "invalid offset",
          }, json)
        end)
      end)
    end)

    it("returns HTTP 405 on invalid method", function()
      local methods = { "DELETE", "PUT", "PATCH", "POST" }
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/routes",
          body = {
            paths = { "/" },
            service = { id = utils.uuid() }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        if methods[i] == "POST" then
          assert.same({
            code    = Errors.codes.OPERATION_UNSUPPORTED,
            name    = Errors.names[Errors.codes.OPERATION_UNSUPPORTED],
            message = "cannot create 'routes' entities when not using a database",
          }, json)

        else
          assert.same({ message = "Method not allowed" }, json)
        end
      end
    end)
  end)

  describe("/routes/{route}", function()
    it("returns HTTP 405 on invalid method", function()
      local methods = { "PUT", "POST" }
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/routes/" .. utils.uuid(),
          body = {
            paths = { "/" },
            service = { id = utils.uuid() }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        if methods[i] ~= "POST" then
          assert.same({
            code    = Errors.codes.OPERATION_UNSUPPORTED,
            name    = Errors.names[Errors.codes.OPERATION_UNSUPPORTED],
            message = "cannot create or update 'routes' entities when not using a database",
          }, json)

        else
          assert.same({ message = "Method not allowed" }, json)
        end
      end
    end)
  end)

  describe("/config", function()
    it("accepts configuration as JSON body", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          _format_version = "1.1",
          consumers = {
            {
              username = "bobby",
            },
          },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)
    end)
    it("accepts configuration as a JSON string", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          {
            "_format_version" : "1.1",
            "consumers" : [
              {
                "username" : "bobby",
              },
            ],
          }
          ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)
    end)
    it("accepts configuration as a YAML string", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          _format_version: "1.1"
          consumers:
          - username: bobby
          ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)
    end)
    it("returns 400 on an invalid config string", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = "bobby tables",
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body =assert.response(res).has.status(400)
      local json = cjson.decode(body)
      assert.same({
        error = "expected a table as input",
      }, json)
    end)
  end)
end)
