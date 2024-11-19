-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require("pl.file")
local clear_license_env = require("spec-ee.helpers").clear_license_env

local function client_send(req)
  local client = helpers.http_client("127.0.0.1", 10001, 20000)
  local res = assert(client:send(req))
  local status, body = res.status, res:read_body()
  client:close()
  return status, body
end

-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

local function count_log_lines(log_file_path, pattern)
  local logs = pl_file.read(log_file_path)
  local _, count = logs:gsub(pattern, "")
  return count
end

for _, strategy in helpers.each_strategy() do
  describe("DP privileged agent publish event hooks during init_worker, strategy#" .. strategy, function()
    local db
    local valid_license

    lazy_setup(function()
      clear_license_env()

      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      valid_license = f:read("*a")
      f:close()

      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"

      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "clustering_data_planes",
        "event_hooks"
      }, {"event-hooks-tester"})

      local service = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      local route = assert(bp.routes:insert {
        protocols = { "http" },
        hosts = { "test" },
        service = service,
      })

      assert(bp.plugins:insert {
        name = "event-hooks-tester",
        route = { id = route.id },
        config = {
        },
      })

      local fixtures = {
        http_mock = {
          webhook_site = [[
            server {
              listen 10001;
              location /webhook {
                content_by_lua_block {
                  local webhook_hit_counter = ngx.shared.webhook_hit_counter
                  ngx.req.read_body()
                  local body_data = ngx.req.get_body_data()
                  local cjson_decode = require("cjson").decode
                  local body = cjson_decode(body_data)
                  if body.source == "foo" and body.event == "bar" then
                    local new_val, err = webhook_hit_counter:incr("hits", 1, 0)
                    if err then
                      ngx.status = 500
                      ngx.say(err)
                     return
                    end
                  end
                  ngx.status = 200
                }
              }
              location /hits {
                content_by_lua_block {
                  local webhook_hit_counter = ngx.shared.webhook_hit_counter
                  local hits = webhook_hit_counter:get("hits")
                  ngx.status = 200
                  if not hits then
                    ngx.say(0)
                  else
                    ngx.say(hits)
                  end
                }
              }
            }
          ]]
        },
      }

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
        log_level = "info",
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
        plugins = "bundled," .. "event-hooks-tester",
        log_level = "info",
        nginx_http_lua_shared_dict = "webhook_hit_counter 1m",
        nginx_worker_processes = 4,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong("servroot")
    end)

    local admin_client, proxy_client
    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client(nil, 9002)
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("trigger event and webhook receive message", function()
      db:truncate("licenses")

      local res = admin_client:post("/event-hooks", {
        body = {
            source = "foo",
            event = "bar",
            handler = "webhook",
            config = {
              url = "http://127.0.0.1:10001/webhook",
            }
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(201, res)

        -- wait for DP receive the event-hooks create event
        ngx.sleep(1)

        local res = assert(admin_client:send {
          method = "POST",
          path = "/licenses",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = { payload = valid_license },
        })
        assert.res_status(201, res)

        helpers.wait_for_all_config_update({
          forced_proxy_port = 9002,
        })

        -- make a request to trigger the event
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "test",
          }
        })

        assert.res_status(200, res)

        ngx.sleep(1)

        helpers.pwait_until(function()
          local status, body = client_send({
            method = "GET",
            path = "/hits",
          })
          assert.equal(200, status)
          local hits = tonumber(body)
          assert.same(1, hits)
        end, 10)
    end)

    it("emit fail", function()
      local event_hooks    = require "kong.enterprise_edition.event_hooks"
      local ok, err = event_hooks.emit("dog", "cat", {
        msg = "msg"
      }, true)

      assert.is_nil(ok)
      assert.equal("source 'dog' is not registered", err)

      local event_hooks    = require "kong.enterprise_edition.event_hooks"
      local ok, err = event_hooks.emit("dog", "cat", {
        msg = "msg"
      })

      assert.is_nil(ok)
      assert.equal("source 'dog' is not registered", err)
    end)
  end)

  describe("DP should work after receiving event_hooks from CP, strategy#" .. strategy, function()

    lazy_setup(function()

      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "clustering_data_planes",
        "event_hooks"
      }, {"event-hooks-tester"})

      local service = assert(bp.services:insert())

      local route = assert(bp.routes:insert({
        hosts = { "test" },
        service = service,
      }))

      assert(bp.plugins:insert {
        name = "event-hooks-tester",
        route = { id = route.id },
        config = {},
      })

      assert(bp.event_hooks:insert({
        source = "foo",
        event = "bar",
        handler = "log",
        config = {},
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot-dp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
        log_level = "debug",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot-dp")
      helpers.stop_kong("servroot")
    end)

    local admin_client, proxy_client
    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client(nil, 9002)
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("event_hooks should works in DP", function()
      helpers.wait_for_all_config_update({
        forced_proxy_port = 9002,
      })

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test",
        }
      })
      assert.res_status(200, res)

      assert.logfile("servroot-dp/logs/error.log").has.line("log callback")
      assert.logfile("servroot-dp/logs/error.log").has.line("Trigger an event in access phase")
    end)
  end)

  describe("event_hooks #" .. strategy, function()
    local admin_client, proxy_client, res
    local log_file_path = "servroot-dp/logs/error.log"
    local error_msg = "event_hooks was called %s times rather than the expected %s times"
    local times = 10
    local count

    local dataplane_env = {
      role = "data_plane",
      database = "off",
      prefix = "servroot-dp",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled," .. "event-hooks-tester",
      nginx_main_worker_processes = 3,
    }

    lazy_setup(function()

      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "clustering_data_planes",
        "event_hooks"
      }, {"event-hooks-tester"})

      local service = assert(bp.services:insert())

      local route = assert(bp.routes:insert({
        hosts = { "test" },
        service = service,
      }))

      assert(bp.plugins:insert {
        name = "event-hooks-tester",
        route = { id = route.id },
        config = {},
      })

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
      }))

      assert(helpers.start_kong(dataplane_env))
    end)

    lazy_teardown(function()
      assert(helpers.stop_kong("servroot-dp"))
      assert(helpers.stop_kong("servroot"))
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client(nil, 9002)
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("should work after creating a event_hooks entity during runtime", function()
      res = admin_client:post("/event-hooks", {
        body = {
          source = "foo",
          event = "bar",
          handler = "log",
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)

      helpers.wait_for_all_config_update({
        forced_proxy_port = 9002,
      })

      for _ = 1, times do -- 10 times to make sure the events are triggered across workers
        res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = { host = "test"}
        })
        assert.res_status(200, res)
      end
      ngx.sleep(3)
      count = count_log_lines(log_file_path, "log callback")
      assert(count == times, string.format(error_msg, count, times))
      count = count_log_lines(log_file_path, "Trigger an event in access phase")
      assert( count == times, string.format(error_msg, count, times))
      helpers.clean_logfile(log_file_path)
    end)

    it("should be called only once for each event after restart", function()
      assert(helpers.restart_kong(dataplane_env))
      proxy_client = helpers.proxy_client(nil, 9002)
      for _ = 1, times do -- 10 times to make sure the events are triggered across workers
        res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "test"}
        })
        assert.res_status(200, res)
      end
      ngx.sleep(3)
      count = count_log_lines(log_file_path, "log callback")
      assert(count == times, string.format(error_msg, count, times))
      count = count_log_lines(log_file_path, "Trigger an event in access phase")
      assert(count == times, string.format(error_msg, count, times))
      helpers.clean_logfile(log_file_path)
    end)
  end)

  describe("DP event_hooks.emit() should work after receiving license from CP, #" .. strategy, function()

    local reset_distribution
    local valid_license

    lazy_setup(function()
      clear_license_env()
      local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
      valid_license = f:read("*a")
      f:close()
      reset_distribution = setup_distribution()
      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "clustering_data_planes",
        "event_hooks",
        "licenses",
      }, {"event-hooks-tester"})

      local service = assert(bp.services:insert())

      local route = assert(bp.routes:insert({
        hosts = { "test" },
        service = service,
      }))

      assert(bp.plugins:insert {
        name = "event-hooks-tester",
        route = { id = route.id },
        config = {},
      })

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot-dp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. "event-hooks-tester",
        log_level = "info",
      }))
    end)

    lazy_teardown(function()
      reset_distribution()
      helpers.stop_kong("servroot-dp")
      helpers.stop_kong("servroot")
    end)

    local admin_client, proxy_client
    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client(nil, 9002)
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("event_hooks should works in DP", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/licenses",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = { payload = valid_license },
      })
      assert.res_status(201, res)

      helpers.wait_for_all_config_update({
        forced_proxy_port = 9002,
      })

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "test",
        }
      })
      assert.res_status(200, res)
      assert.equal("true", res.headers["x-event-hooks-enabled"])
      assert.logfile("servroot-dp/logs/error.log").has.no.line("failed to emit event: source 'foo' is not registered")
    end)
  end)
end
