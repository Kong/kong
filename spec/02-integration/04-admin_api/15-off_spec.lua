local cjson    = require "cjson"
local lyaml    = require "lyaml"
local utils    = require "kong.tools.utils"
local pl_utils = require "pl.utils"
local helpers  = require "spec.helpers"
local Errors   = require "kong.db.errors"
local mocker   = require("spec.fixtures.mocker")


local WORKER_SYNC_TIMEOUT = 10
local LMDB_MAP_SIZE = "10m"
local TEST_CONF = helpers.test_conf


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
      lmdb_map_size = LMDB_MAP_SIZE,
      stream_listen = "127.0.0.1:9011",
      nginx_conf = "spec/fixtures/custom_nginx.template",
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
                username = "bobby_in_json_body",
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        assert.response(res).has.status(201)
      end)

      it("accepts configuration as YAML body", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = helpers.unindent([[
            _format_version: "1.1"
            consumers:
              - username: "bobby_in_yaml_body"
          ]]),
          headers = {
            ["Content-Type"] = "text/yaml"
          },
        })

        assert.response(res).has.status(201)
      end)

      it("accepts configuration as a JSON string under `config` JSON key", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            {
              "_format_version" : "1.1",
              "consumers" : [
                {
                  "username" : "bobby_in_json_under_config"
                }
              ]
            }
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        assert.response(res).has.status(201)
      end)

      it("accepts configuration as a YAML string under `config` JSON key", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = helpers.unindent([[
              _format_version: "1.1"
              consumers:
                - username: "bobby_in_yaml_under_config"
            ]]),
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
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
                  "username" : "previous"
                }
              ]
            }
            ]],
            type = "json",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
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
              "username" : "bobby-]] .. i .. [["
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

        helpers.wait_until(function()
          client:close()
          client = assert(helpers.admin_client())
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

      it("accepts configuration containing null as a YAML string", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            _format_version: "1.1"
            routes:
            - paths:
              - "/"
              service: null
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)
      end)

      it("hides workspace related fields from /config response", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            _format_version: "1.1"
            services:
            - name: my-service
              id: 0855b320-0dd2-547d-891d-601e9b38647f
              url: https://example.com
              plugins:
              - name: file-log
                id: 0611a5a9-de73-5a2d-a4e6-6a38ad4c3cb2
                config:
                  path: /tmp/file.log
              - name: key-auth
                id: 661199ff-aa1c-5498-982c-d57a4bd6e48b
              routes:
              - name: my-route
                id: 481a9539-f49c-51b6-b2e2-fe99ee68866c
                paths:
                - /
            consumers:
            - username: my-user
              id: 4b1b701d-de2b-5588-9aa2-3b97061d9f52
              keyauth_credentials:
              - key: my-key
                id: 487ab43c-b2c9-51ec-8da5-367586ea2b61
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.response(res).has.status(201)
        local entities = cjson.decode(body)

        assert.is_nil(entities.workspaces)
        assert.is_nil(entities.consumers["4b1b701d-de2b-5588-9aa2-3b97061d9f52"].ws_id)
        assert.is_nil(entities.keyauth_credentials["487ab43c-b2c9-51ec-8da5-367586ea2b61"].ws_id)
        assert.is_nil(entities.plugins["0611a5a9-de73-5a2d-a4e6-6a38ad4c3cb2"].ws_id)
        assert.is_nil(entities.plugins["661199ff-aa1c-5498-982c-d57a4bd6e48b"].ws_id)
        assert.is_nil(entities.routes["481a9539-f49c-51b6-b2e2-fe99ee68866c"].ws_id)
        assert.is_nil(entities.services["0855b320-0dd2-547d-891d-601e9b38647f"].ws_id)
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

      it("sparse responses are correctly generated", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            {
              "_format_version" : "1.1",
              "plugins": [{
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "key-auth",
                "enabled": true,
                "protocols": ["http", "https"]
              }, {
                "name": "cors",
                "config": {
                  "credentials": true,
                  "exposed_headers": ["*"],
                  "headers": ["*"],
                  "methods": ["*"],
                  "origins": ["*"],
                  "preflight_continue": true
                },
                "enabled": true,
                "protocols": ["http", "https"]
              }]
            }
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(400)
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
        local config = assert(lyaml.load(json.config))
        assert.same({
          _format_version = "2.1",
          _transform = false,
          consumers = {
            { id = "d885e256-1abe-5e24-80b6-8f68fe59ea8e",
              created_at = 1566863706,
              username = "bobo",
              custom_id = lyaml.null,
              tags = lyaml.null,
            },
          },
        }, config)
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

    it("updates stream subsystem config", function()
      local res = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          _format_version: "1.1"
          services:
          - connect_timeout: 60000
            host: 127.0.0.1
            name: mock
            port: 15557
            protocol: tcp
            routes:
            - name: mock_route
              protocols:
              - tcp
              destinations:
              - port: 9011
          ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.response(res).has.status(201)

      helpers.wait_until(function()
        local sock = ngx.socket.tcp()
        assert(sock:connect("127.0.0.1", 9011))
        assert(sock:send("hi\n"))
        local pok = pcall(helpers.wait_until, function()
          return sock:receive() == "hi"
        end, 1)
        sock:close()
        return pok == true
      end)
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
          healthchecks:
            passive:
              healthy:
                successes: 1
              unhealthy:
                http_failures: 1
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

      table.sort(json.data, function(t1, t2)
        return t1.target < t2.target
      end)

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
      lmdb_map_size = LMDB_MAP_SIZE,
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
      lmdb_map_size = LMDB_MAP_SIZE,
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

    local key = "unique_references\\|\\|unique_foreign:" .. foreigns.data[1].id
    local handle = io.popen("resty --main-conf \"lmdb_environment_path " ..
                            TEST_CONF.prefix .. "/" .. TEST_CONF.lmdb_environment_path ..
                            ";\" spec/fixtures/dump_lmdb_key.lua " .. key)
    local result = handle:read("*a")
    handle:close()

    local cached_reference = assert(require("kong.db.declarative.marshaller").unmarshall(result))
    assert.same(cached_reference, references.data[1])

    local cache = {
      get = function(_, k)
        if k ~= "unique_references||unique_foreign:" .. foreigns.data[1].id then
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

    -- TODO: figure out how to mock LMDB in busted
    -- local unique_reference, err, err_t = db.unique_references:select_by_unique_foreign({
    --   id = foreigns.data[1].id,
    -- })

    -- assert.is_nil(err)
    -- assert.is_nil(err_t)

    -- assert.equal(references.data[1].id, unique_reference.id)
    -- assert.equal(references.data[1].note, unique_reference.note)
    -- assert.equal(references.data[1].unique_foreign.id, unique_reference.unique_foreign.id)
  end)
end)
