-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local resty_str = require "resty.string"


local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid


local PLUGIN_NAME = "konnect-application-auth"


local function hash_key(key)
  local sha256 = resty_sha256:new()
  sha256:update(key)
  return resty_str.to_hex(sha256:final())
end


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (integration v2 keyauth) [#" .. strategy .. "]", function()
    local client
    local key_auth_service_consumer_group
    local scope = uuid()
    local stratID = uuid()
    local stratID2 = uuid()
    local consumer_group1
    local consumer_group2


    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "konnect_applications", "services", "routes"
      }, { PLUGIN_NAME, "ctx-checker" })

      -- Key auth
      local key_auth_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      bp.routes:insert({
        service = key_auth_service,
        hosts = { "keyauth.konghq.com" },
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = key_auth_service,
        config = {
          scope = scope,
          auth_type = "v2-strategies",
          v2_strategies = {
            key_auth = {
              {
                strategy_id = stratID,
                config = {
                  key_names = {'xapikey'}
                }
              },
              {
                strategy_id = stratID2,
                config = {
                  key_names = {'zapikey'}
                }
              }
            }
          }
        },
      })

      db.konnect_applications:insert({
        client_id = hash_key("opensesame"),
        scopes = { scope },
        auth_strategy_id = stratID
      })

      db.konnect_applications:insert({
        client_id = hash_key("OPENIT"),
        scopes = { scope },
        auth_strategy_id = stratID2
      })

      -- Consumer group
      key_auth_service_consumer_group = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      bp.routes:insert({
        service = key_auth_service_consumer_group,
        hosts = { "keyauthconsumergroup.konghq.com" },
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = key_auth_service_consumer_group,
        config = {
          scope = scope,
          auth_type = "v2-strategies",
          v2_strategies = {
            key_auth = {
                {
                strategy_id = stratID,
                config = {
                  key_names = {'xapikey'}
                }
              }
            }
          }
        },
      })

      bp.plugins:insert {
        name = "post-function",
          service = key_auth_service_consumer_group,
          config = {
            header_filter = {[[
              local c = kong.client.get_consumer_groups()
              if c then
                local names = {}
                for i, v in ipairs(c) do
                  table.insert(names, v.name)
                end
                kong.response.set_header("x-consumer-groups-kaa", table.concat(names,","))
              end
              kong.response.set_header("x-test", "kaa")
            ]]}
          }
      }

      db.konnect_applications:insert({
        client_id = hash_key("opendadoor"),
        scopes = { scope },
        auth_strategy_id = stratID,
        consumer_groups = {"imindaband1","imindaband2"}
      })

      db.konnect_applications:insert({
        client_id = hash_key("opendadoor2"),
        scopes = { scope },
        auth_strategy_id = stratID,
        consumer_groups = {"idontexist"}
      })

      consumer_group1 = db.consumer_groups:insert({
        name = "imindaband1"
      })

      consumer_group2 = db.consumer_groups:insert({
        name = "imindaband2"
      })

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME .. ",ctx-checker",
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)
    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)
    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("Key-auth", function ()
      it("returns 401 if api key found", function ()
        local res = client:get("/request", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 401 if api key in query is invalid", function ()
        local res = client:get("/request?xapikey=derp", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 401 if api key in header is invalid", function ()
        local res = client:get("/request", {
          headers = {
            xapikey = "derp",
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 200 if api key found in query", function ()
        local res = client:get("/request?xapikey=opensesame", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

       assert.res_status(200, res)
      end)

      it("returns 200 if api key found in headers", function ()
        local res = client:get("/request", {
          headers = {
            xapikey = "opensesame",
            host = "keyauth.konghq.com"
          }
        })

       assert.res_status(200, res)
      end)

      it("returns 200 if api key found in query in second strat", function ()
        local res = client:get("/request?zapikey=OPENIT", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

       assert.res_status(200, res)
      end)

    end)

    describe("Key-auth consumer groups", function()

      it("maps the consumer groups if found", function()
        local res = client:get("/request?xapikey=opendadoor", {
            headers = {
                host = "keyauthconsumergroup.konghq.com"
            }
        })

        assert.res_status(200, res)
        assert.are.same(consumer_group1.name .. "," .. consumer_group2.name, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

      it("doesnt map the consumer groups if not found", function()
        local res = client:get("/request?xapikey=opendadoor2", {
            headers = {
                host = "keyauthconsumergroup.konghq.com"
            }
        })

        assert.res_status(200, res)
        assert.are.same(nil, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

      it("doesnt map the consumer groups if request fails", function()
        local res = client:get("/request", {
            headers = {
                host = "keyauthconsumergroup.konghq.com"
            }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
        assert.are.same(nil, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

    end)
  end)
end
