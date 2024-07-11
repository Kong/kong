-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson = require "cjson"
local encode_base64 = ngx.encode_base64

local ADMIN_PORT = helpers.get_available_port()
local ADMIN_PORT2 = helpers.get_available_port()
local ADMIN_GUI_PORT = helpers.get_available_port()
local ADMIN_GUI_PORT2 = helpers.get_available_port()
local PROXY_PORT = helpers.get_available_port()
local PROXY_PORT2 = helpers.get_available_port()
local CLUSTER_PORT = helpers.get_available_port()
local CLUSTER_PORT2 = helpers.get_available_port()
local CLUSTER_TELEMETRY_PORT = helpers.get_available_port()
local CLUSTER_TELEMETRY_PORT2 = helpers.get_available_port()

for _, strategy in helpers.each_strategy({"postgres"}) do
describe("Keyring recovery #" .. strategy, function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "consumers",
      "upstreams",
      "targets",
      "keyring_meta",
      "keyring_keys",
    })

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("ensure keyring works", function()
    it("/keyring", function()
      helpers.wait_until(function()
        local client = helpers.admin_client()
        local res = assert(client:send {
          method = "GET",
          path = "/keyring",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        client:close()
        return json.active ~= nil
      end, 5)

      local res = assert(admin_client:send {
        method = "GET",
        path = "/keyring/active",
      })
      assert.res_status(200, res)
    end)

    it("correct privat key recovers keys", function()
      local privkey_pem, err = pl_file.read("spec-ee/fixtures/keyring/key.pem")
      assert.is_nil(err)

      local res = assert(admin_client:send {
        method = "POST",
        path = "/keyring/recover",
        body = {
          ["recovery_private_key"] = privkey_pem,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("successfully recovered 1 keys", json.message)
    end)

    it("wrong private key doesn't recover keys", function()
      local key = assert(require("resty.openssl.pkey").new({type="EC"}))
      local privkey_pem = assert(key:to_PEM("private"))

      local res = assert(admin_client:send {
        method = "POST",
        path = "/keyring/recover",
        body = {
          ["recovery_private_key"] = privkey_pem,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("successfully recovered 0 keys", json.message)
      assert.equal(1, json.not_recovered and #json.not_recovered or 0)
    end)
  end)

end)

describe("Keyring recovery push config #" .. strategy, function()
  local admin_client1, admin_client2
  local proxy_client1, proxy_client2
  local function start_cps_dps()
    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      database = strategy,
      db_update_frequency = 0.1,
      admin_listen = "127.0.0.1:" .. ADMIN_PORT,
      cluster_listen = "127.0.0.1:" .. CLUSTER_PORT,
      admin_gui_listen = "127.0.0.1:" .. ADMIN_GUI_PORT,
      cluster_telemetry_listen = "127.0.0.1:" .. CLUSTER_TELEMETRY_PORT,
      prefix = "cp1",
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      database = strategy,
      db_update_frequency = 0.1,
      admin_listen = "127.0.0.1:" .. ADMIN_PORT2,
      cluster_listen = "127.0.0.1:" .. CLUSTER_PORT2,
      admin_gui_listen = "127.0.0.1:" .. ADMIN_GUI_PORT2,
      cluster_telemetry_listen = "127.0.0.1:" .. CLUSTER_TELEMETRY_PORT2,
      prefix = "cp2",
      nginx_worker_processes = 1,
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    assert(helpers.start_kong({
      role = "data_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      database = "off",
      cluster_control_plane = "127.0.0.1:" .. CLUSTER_PORT,   -- cp1
      proxy_listen = "0.0.0.0:" .. PROXY_PORT,
      cluster_telemetry_endpoint = "127.0.0.1:" .. CLUSTER_TELEMETRY_PORT,
      prefix = "dp1",
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    assert(helpers.start_kong({
      role = "data_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      database = "off",
      cluster_control_plane = "127.0.0.1:" .. CLUSTER_PORT2,  -- cp2
      proxy_listen = "0.0.0.0:" .. PROXY_PORT2,
      cluster_telemetry_endpoint = "127.0.0.1:" .. CLUSTER_TELEMETRY_PORT2,
      prefix = "dp2",
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    helpers.wait_for_file_contents("cp1/pids/nginx.pid")
    helpers.wait_for_file_contents("cp2/pids/nginx.pid")
    helpers.wait_for_file_contents("dp1/pids/nginx.pid")
    helpers.wait_for_file_contents("dp2/pids/nginx.pid")
  end

  local function stop_cps_dps()
    helpers.stop_kong("cp1")
    helpers.stop_kong("cp2")
    helpers.stop_kong("dp1")
    helpers.stop_kong("dp2")
  end

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "consumers",
      "upstreams",
      "targets",
      "keyring_meta",
      "keyring_keys",
      "basicauth_credentials",
    })

    local consumer = bp.consumers:insert {
      username = "bob",
    }

    local service = bp.services:insert {
      name = "test",
      path = "/anything",
    }

    local route = bp.routes:insert {
      service = service,
      paths = { "/test" },
    }

    bp.plugins:insert {
      name = "basic-auth",
      route = { id = route.id },
    }

    start_cps_dps()

    helpers.clean_logfile("dp1/logs/error.log")
    helpers.clean_logfile("dp2/logs/error.log")

    admin_client1 = assert(helpers.admin_client(nil, ADMIN_PORT))

    -- create basicauth_credentials after kong is started
    -- so that they'll be encryped by the key.
    local res = assert(admin_client1:send({
      method = "POST",
      path = "/basic-auths",
      body = {
        username = "bob",
        password = "kong",
        consumer = { id = consumer.id },
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))
    local body = cjson.decode(assert.res_status(201, res))
    assert.same("bob", body.username)
    -- password will be hashed with salt
    assert.same(consumer.id, body.consumer.id)

    admin_client1:close()
  end)

  lazy_teardown(function()
    stop_cps_dps()
  end)

  before_each(function()
    admin_client1 = assert(helpers.admin_client(nil, ADMIN_PORT))
    admin_client2 = assert(helpers.admin_client(nil, ADMIN_PORT2))
    proxy_client1 = assert(helpers.proxy_client(nil, PROXY_PORT))
    proxy_client2 = assert(helpers.proxy_client(nil, PROXY_PORT2))

    helpers.clean_logfile("cp1/logs/error.log")
    helpers.clean_logfile("cp2/logs/error.log")
    helpers.clean_logfile("dp1/logs/error.log")
    helpers.clean_logfile("dp2/logs/error.log")
  end)

  after_each(function()
    if admin_client1 then
      admin_client1:close()
    end
    if admin_client2 then
      admin_client2:close()
    end
    if proxy_client1 then
      proxy_client1:close()
    end
    if proxy_client2 then
      proxy_client2:close()
    end
  end)

  it("everything is ok at first", function()
    local res = admin_client1:send {
      method = "GET",
      path = "/keyring",
    }
    local body = cjson.decode(assert.res_status(200, res))
    assert.same(1, #body.ids)
    local active_key = body.active

    local res = admin_client2:send {
      method = "GET",
      path = "/keyring",
    }
    body = cjson.decode(assert.res_status(200, res))
    assert.same(1, #body.ids)
    assert.same(active_key, body.active)

    assert.with_timeout(20)
    .with_step(0.5)
    .eventually(function()
      res = proxy_client1:send {
        method = "GET",
        path = "/test",
        headers = {
          ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
        }
      }
      assert.res_status(200, res)

      res = proxy_client2:send {
        method = "GET",
        path = "/test",
        headers = {
          ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
        }
      }
      assert.res_status(200, res)
    end)
    .has_no_error()
  end)

  it("after recreating cp and dp, cp should fail to push the initial config", function()
    stop_cps_dps()
    start_cps_dps()

    assert.logfile("cp1/logs/error.log").has.line("unable to export initial config from database:", true, 5)
    assert.logfile("cp2/logs/error.log").has.line("unable to export initial config from database:", true, 5)
    assert.logfile("cp1/logs/error.log").has.line("unable to send initial configuration to data plane:", true, 5)
    assert.logfile("cp2/logs/error.log").has.line("unable to send initial configuration to data plane:", true, 5)

    admin_client1 = assert(helpers.admin_client(nil, ADMIN_PORT))
    admin_client2 = assert(helpers.admin_client(nil, ADMIN_PORT2))
    proxy_client1 = assert(helpers.proxy_client(nil, PROXY_PORT))
    proxy_client2 = assert(helpers.proxy_client(nil, PROXY_PORT2))

    local res = admin_client1:send {
      method = "GET",
      path = "/keyring",
    }
    local body = cjson.decode(assert.res_status(200, res))
    assert.same(0, #body.ids)

    res = admin_client2:send {
      method = "GET",
      path = "/keyring",
    }
    body = cjson.decode(assert.res_status(200, res))
    assert.same(0, #body.ids)

    res = proxy_client1:send {
      method = "GET",
      path = "/test",
      headers = {
        ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
      }
    }
    assert.res_status(404, res)

    res = proxy_client2:send {
      method = "GET",
      path = "/test",
      headers = {
        ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
      }
    }
    assert.res_status(404, res)
  end)

  it("dp should get back to normal after cp recovers the keyring", function()
    local privkey_pem, err = pl_file.read("spec-ee/fixtures/keyring/key.pem")
    assert.is_nil(err)

    local res = assert(admin_client1:send {
      method = "POST",
      path = "/keyring/recover",
      body = {
        ["recovery_private_key"] = privkey_pem,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.same("successfully recovered 1 keys", json.message)

    assert.logfile("cp2/logs/error.log").has.line("received clustering:push_config event for keyring:recover", true, 5)
    assert.logfile("dp1/logs/error.log").has.line("received reconfigure frame from control plane with timestamp", true, 5)
    assert.logfile("dp2/logs/error.log").has.line("received reconfigure frame from control plane with timestamp", true, 5)

    assert.with_timeout(20)
    .with_step(0.5)
    .eventually(function()
      res = proxy_client1:send {
        method = "GET",
        path = "/test",
        headers = {
          ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
        }
      }
      assert.res_status(200, res)

      res = proxy_client2:send {
        method = "GET",
        path = "/test",
        headers = {
          ["Authorization"] = "Basic " .. encode_base64("bob:kong"),
        }
      }
      assert.res_status(200, res)
    end)
    .has_no_error()
  end)
end)
end
