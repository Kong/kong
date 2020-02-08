local cjson    = require "cjson"
local utils    = require "kong.tools.utils"
local pl_utils = require "pl.utils"
local helpers  = require "spec.helpers"
local Errors   = require "kong.db.errors"
local mocker   = require("spec.fixtures.mocker")

local WORKER_SYNC_TIMEOUT = 10


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
      mem_cache_size = "10m",
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
    describe("POST", function()
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

      it("fails with 413 and preserves previous cache if config does not fit in cache", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            {
              "_format_version" : "1.1",
              "consumers" : [
                {
                  "username" : "previous",
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

        helpers.wait_until(function()
          res = assert(client:send {
            method = "GET",
            path = "/consumers/previous",
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = res:read_body()
          local json = cjson.decode(body)
          if res.status == 200 and json.username == "previous" then
            return true
          end
        end, WORKER_SYNC_TIMEOUT)

        client:close()
        client = assert(helpers.admin_client())

        local consumers = {}
        for i = 1, 20000 do
          table.insert(consumers, [[
            {
              "username" : "bobby-]] .. i .. [[",
            }
          ]])
        end
        local config = [[
        {
          "_format_version" : "1.1",
          "consumers" : [
        ]] .. table.concat(consumers, ", ") .. [[
          ]
        }
        ]]
        res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = config,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(413)

        client:close()
        client = assert(helpers.admin_client())

        helpers.wait_until(function()
          res = assert(client:send {
            method = "GET",
            path = "/consumers/previous",
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = res:read_body()
          local json = cjson.decode(body)
          if res.status == 200 and json.username == "previous" then
            return true
          end
        end, WORKER_SYNC_TIMEOUT)

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

      it("can reload upstreams (regression test)", function()
        local config = [[
          _format_version: "1.1"
          services:
          - host: foo
            routes:
            - paths:
              - "/"
          upstreams:
          - name: "foo"
            targets:
            - target: 10.20.30.40
        ]]
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = config,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)

        client:close()
        client = helpers.admin_client()

        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = config,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)
      end)

      it("returns 304 if checking hash and configuration is identical", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config?check_hash=1",
          body = {
            config = [[
            _format_version: "1.1"
            consumers:
            - username: bobby_tables
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)

        client:close()
        client = helpers.admin_client()

        res = assert(client:send {
          method = "POST",
          path = "/config?check_hash=1",
          body = {
            config = [[
            _format_version: "1.1"
            consumers:
            - username: bobby_tables
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(304)
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

        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({
          code = 14,
          fields = {
            error ="failed parsing declarative configuration: expected an object",
          },
          message = [[declarative config is invalid: ]] ..
                    [[{error="failed parsing declarative configuration: ]] ..
                    [[expected an object"}]],
          name = "invalid declarative configuration",
        }, json)
      end)

      it("returns 400 on a validation error", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            _format_version: "1.1"
            services:
            - port: -12
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({
          code = 14,
          fields = {
            services = {
              {
                host = "required field missing",
                port = "value should be between 0 and 65535",
              }
            }
          },
          message = [[declarative config is invalid: ]] ..
                    [[{services={{host="required field missing",]] ..
                    [[port="value should be between 0 and 65535"}}}]],
          name = "invalid declarative configuration",
        }, json)
      end)

      it("returns 400 when given no input", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
        })

        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({
          message = "expected a declarative configuration",
        }, json)
      end)
    end)

    describe("GET", function()
      it("returns back the configuration", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            _format_version = "1.1",
            consumers = {
              {
                username = "bobo",
                id = "d885e256-1abe-5e24-80b6-8f68fe59ea8e",
                created_at = 1566863706,
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)

        local res = assert(client:send {
          method = "GET",
          path = "/config",
        })

        local body = assert.response(res).has.status(200)
        local json = cjson.decode(body)
        local expected_config = "_format_version: '1.1'\n" ..
          "consumers:\n" ..
          "- created_at: 1566863706\n" ..
          "  username: bobo\n" ..
          "  id: d885e256-1abe-5e24-80b6-8f68fe59ea8e\n"
        assert.same(expected_config, json.config)
      end)
    end)

    it("can load large declarative config (regression test)", function()
      local config = assert(pl_utils.readfile("spec/fixtures/burst.yml"))
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = config,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)
    end)
  end)

  describe("/upstreams", function()
    it("can set target health without port", function()
      local config = [[
        _format_version: "1.1"
        services:
        - host: foo
          routes:
          - paths:
            - "/"
        upstreams:
        - name: "foo"
          targets:
          - target: 10.20.30.40
      ]]

      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = config,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)

      local res = assert(client:send {
        method = "POST",
        path = "/upstreams/foo/targets/c830b59e-59cc-5392-adfd-b414d13adfc4/10.20.30.40/unhealthy",
      })

      assert.response(res).has.status(204)

      client:close()
    end)

    it("targets created missing ports listed with ports", function()
      local config = [[
        _format_version: "1.1"
        services:
        - host: foo
          routes:
          - paths:
            - "/"
        upstreams:
        - name: "foo"
          targets:
          - target: 10.20.30.40
          - target: 50.60.70.80:90
      ]]

      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = config,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)

      local res = assert(client:send {
        method = "GET",
        path = "/upstreams/foo/targets/all",
      })

      local body = assert.response(res).has.status(200)
      local json = cjson.decode(body)
      assert.same("10.20.30.40:8000", json.data[1].target)
      assert.same("50.60.70.80:90", json.data[2].target)

      client:close()
    end)
  end)
end)

describe("Admin API (concurrency tests) #off", function()
  local client

  before_each(function()
    assert(helpers.start_kong({
      database = "off",
      nginx_worker_processes = 8,
      mem_cache_size = "10m",
    }))

    client = assert(helpers.admin_client())
  end)

  after_each(function()
    helpers.stop_kong(nil, true)

    if client then
      client:close()
    end
  end)

  it("succeeds with 200 and replaces previous cache if config fits in cache", function()
    -- stress test to check for worker concurrency issues
    for k = 1, 100 do
      if client then
        client:close()
        client = helpers.admin_client()
      end
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          {
            "_format_version" : "1.1",
            "consumers" : [
              {
                "username" : "previous",
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
      client:close()

      local consumers = {}
      for i = 1, 10 do
        table.insert(consumers, [[
          {
            "username" : "bobby-]] .. k .. "-" .. i .. [[",
          }
        ]])
      end
      local config = [[
      {
        "_format_version" : "1.1",
        "consumers" : [
      ]] .. table.concat(consumers, ", ") .. [[
        ]
      }
      ]]

      client = assert(helpers.admin_client())
      res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = config,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)

      client:close()

      helpers.wait_until(function()
        client = assert(helpers.admin_client())
        res = assert(client:send {
          method = "GET",
          path = "/consumers/previous",
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        client:close()

        return res.status == 404
      end, WORKER_SYNC_TIMEOUT)

      helpers.wait_until(function()
        client = assert(helpers.admin_client())

        res = assert(client:send {
          method = "GET",
          path = "/consumers/bobby-" .. k .. "-10",
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = res:read_body()
        client:close()

        if res.status ~= 200 then
          return false
        end

        local json = cjson.decode(body)
        return "bobby-" .. k .. "-10" == json.username
      end, WORKER_SYNC_TIMEOUT)
    end
  end)
end)

describe("Admin API #off with Unique Foreign #unique", function()
  local client

  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
      plugins = "unique-foreign",
      nginx_worker_processes = 1,
      mem_cache_size = "10m",
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


  it("unique foreign works with dbless", function()
    local config = [[
        _format_version: "1.1"
        unique_foreigns:
        - name: name
          unique_references:
          - note: note
      ]]

    local res = assert(client:send {
      method = "POST",
      path = "/config",
      body = {
        config = config,
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)

    local res = assert(client:get("/unique-foreigns"))
    local body = assert.res_status(200, res)
    local foreigns = cjson.decode(body)


    assert.equal(foreigns.data[1].name, "name")

    local res = assert(client:get("/unique-references"))
    local body = assert.res_status(200, res)
    local references = cjson.decode(body)

    assert.equal(references.data[1].note, "note")
    assert.equal(references.data[1].unique_foreign.id, foreigns.data[1].id)


    local res = assert(client:get("/cache/unique_references|unique_foreign:" ..
                                  foreigns.data[1].id))
    local body = assert.res_status(200, res)
    local cached_reference = cjson.decode(body)

    assert.same(cached_reference, references.data[1])

    local cache = {
      get = function(_, k)
        if k ~= "unique_references|unique_foreign:" .. foreigns.data[1].id then
          return nil
        end

        return cached_reference
      end
    }

    mocker.setup(finally, {
      kong = {
        core_cache = cache,
      }
    })

    local _, db = helpers.get_db_utils("off", {}, {
      "unique-foreign"
    })

    local i = 1
    while true do
      local n, v = debug.getupvalue(db.unique_references.strategy.select_by_field, i)
      if not n then
        break
      end

      if n == "select_by_key" then
        local j = 1
        while true do
          local n, v = debug.getupvalue(v, j)
          if not n then
            break
          end

          if n == "kong" then
            v.core_cache = cache
            break
          end

          j = j + 1
        end

        break
      end

      i = i + 1
    end

    local unique_reference, err, err_t = db.unique_references:select_by_unique_foreign({
      id = foreigns.data[1].id,
    })

    assert.is_nil(err)
    assert.is_nil(err_t)

    assert.equal(references.data[1].id, unique_reference.id)
    assert.equal(references.data[1].note, unique_reference.note)
    assert.equal(references.data[1].unique_foreign.id, unique_reference.unique_foreign.id)
  end)
end)
