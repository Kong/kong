-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local function any(t, p)
  return #tablex.filter(t, p) > 0
end

local function post(client, path, body, headers, expected_status)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  if any(tablex.keys(body), function(x) return x:match( "%[%]$") end) then
    headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or 201, res))
end

local function delete(client, path, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "DELETE",
    path = path,
    headers = headers
  })
  assert.res_status(expected_status or 204, res)
end


local dp_admin_port = 9999
local dp_fixtures = {
  http_mock = {
    dp_admin_api = ([[
      server {
        access_log logs/admin_access.log;
        error_log   logs/admin_error.log debug;

        listen %s;
        location / {
          default_type application/json;
          content_by_lua_block {
            Kong.admin_content()
          }
          header_filter_by_lua_block {
            Kong.admin_header_filter()
          }
        }
      }
    ]]):format(dp_admin_port),
  },
}

local function dp_admin()
  return assert(helpers.proxy_client(10000, dp_admin_port))
end

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- this might not be necessary depending on how much busted isolates test
-- suites, but it doesn't hurt
local function setup_env()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end
  end
end


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()
    local reset_env

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "upstreams",
        "targets",
        "certificates",
        "clustering_data_planes",
        "licenses",
      }) -- runs migrations

      reset_env = setup_env()

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, dp_fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
      reset_env()
    end)

    local admin_client
    before_each(function()
      admin_client = helpers.admin_client(10000)
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
    end)

    it("syncs correctly the workspaces info", function()
      local function delayed_get(url, headers, expect)
        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          local res = proxy_client:get(url, { headers  = headers })

          local status = res and res.status
          proxy_client:close()
          if status == expect then
            return true
          end
        end, 10)
      end

      post(admin_client, "/workspaces/", { name = "ws1" })
      post(admin_client, "/ws1/services", { name = "mockbin-service-ws1", url = "https://127.0.0.1:15556/request", })
      post(admin_client, "/ws1/services/mockbin-service-ws1/routes", { name="rws1", paths = { "/ws1-route"}})
      post(admin_client, "/ws1/services/mockbin-service-ws1/plugins", {name = "key-auth"})
      post(admin_client, "/ws1/consumers", { username = "u1" })
      post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u1" })
      -- post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u2" })

      post(admin_client, "/ws1/consumer_groups", { name = "cg1" })
      post(admin_client, "/ws1/consumer_groups/cg1/consumers", { consumer = "u1" })

      -- route/consumer is ok
      delayed_get("/ws1-route", { apikey= 'u1' }, 200)

      -- the key has to match
      delayed_get("/ws1-route", { apikey= 'foo' }, 401)

      -- shorter url doesn't match
      delayed_get("/", { apikey= 'u1' }, 404)

      -- default ws with a "/" route and a consumer with same creds
      post(admin_client, "/default/services", {name = "mockbin-service-default", url = "https://127.0.0.1:15556/request"})
      post(admin_client, "/default/services/mockbin-service-default/routes", {paths = { "/"}})
      post(admin_client, "/default/services/mockbin-service-default/plugins", {name = "key-auth"})
      post(admin_client, "/default/consumers", { username = "u1" })
      post(admin_client, "/default/consumers/u1/key-auth", { key = "u1" })

      -- route/consumer is ok
      delayed_get("/", { apikey= 'u1' }, 200)

      -- the key has to match
      delayed_get("/", { apikey= 'foo' }, 401)

      -- remove ws1 route to make sure we're matching the new one
      delete(admin_client, "/ws1/routes/rws1")

      -- match (but hopefully the one from default)
      delayed_get("/ws1-route", { apikey= 'u1' }, 200)
      delayed_get("/", { apikey= 'u1' }, 200)

      -- delete consumer from ws1
      delete(admin_client, "/ws1/consumers/u1/key-auth/u1")

      -- match, from consumer from default ws
      delayed_get("/", { apikey= 'u1' }, 200)

      -- add u2 key to ws1 consumer
      post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u2" })

      -- doesn't work, wrong WS
      delayed_get("/", { apikey= 'u2' }, 401)
    end)

    it("propagates license updates from the control plane", function()
      local mock_license_data = assert(helpers.file.read("spec-ee/fixtures/mock_license.json"))

      local mock_license = assert(cjson.decode(mock_license_data))
      local mock_license_key = assert.not_nil(mock_license.license.payload.license_key)
      local mock_license_signature = assert.not_nil(mock_license.license.signature)

      local function list_licenses(client)
        local res, err = client:send({
          method = "GET",
          path = "/licenses/",
        })

        assert.is_nil(err)
        assert.res_status(200, res)

        local list = assert.response(res).has.jsonbody()
        assert.not_nil(list.data, "invalid response from /licenses/")

        -- hydrate
        for i = 1, #list.data do
          local item = list.data[i]
          local json = assert(cjson.decode(item.payload))
          item.payload = assert.not_nil(json.license.payload)
          item.signature = assert.not_nil(json.license.signature)
        end

        return list
      end


      local function get_license_report(client)
        local res, err = client:send({
          method = "GET",
          path = "/license/report",
        })

        assert.is_nil(err)
        assert.res_status(200, res)

        local report = assert.response(res).has.jsonbody()
        assert.not_nil(report.license_key, "missing license_key in /license/report response")
        return report
      end


      local function assert_no_licenses(client)
        local list = list_licenses(client)

        assert.same({
          data = {},
          next = ngx.null,
        }, list)

        local report = get_license_report(client)
        assert.equals("UNLICENSED", report.license_key)
      end


      local function add_license(client)
        local res, err = client:send({
          method = "POST",
          path = "/licenses/",
          body = cjson.encode({ payload = mock_license_data }),
          headers = {
            ["content-type"] = "application/json",
          },
        })

        assert.is_nil(err)
        assert.res_status(201, res)
      end

      local function assert_has_license(client)
        local list
        -- need to retry+delay here to account for latency in
        -- CP->DP sync
        helpers.wait_until(function()
          list = list_licenses(client)
          return list and list.data and #list.data > 0
        end, 10, 0.5)

        assert.equals(1, #list.data, "expected 1 license from /licenses/ list")
        assert.equals(mock_license_key, list.data[1].payload.license_key)
        assert.equals(mock_license_signature, list.data[1].signature)

        helpers.wait_until(function()
          local report = get_license_report(client)
          return report.license_key == mock_license_key
        end, 10, 0.5)
      end

      local dp_admin_client = dp_admin()

      -- sanity
      assert_no_licenses(admin_client)
      assert_no_licenses(dp_admin_client)

      add_license(admin_client)

      assert_has_license(admin_client)
      assert_has_license(dp_admin_client)
    end)
  end)
end
