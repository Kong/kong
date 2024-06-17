local helpers    = require "spec.helpers"
local uuid       = require "kong.tools.uuid"
local cjson      = require "cjson"


local strip = require("kong.tools.string").strip
local split = require("kong.tools.string").split


for _, strategy in helpers.each_strategy() do
  describe("Plugin: syslog (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc
    local platform

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route1 = bp.routes:insert {
        hosts = { "logging.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "logging2.test" },
      }

      local route3 = bp.routes:insert {
        hosts = { "logging3.test" },
      }

      local route4 = bp.routes:insert {
        hosts = { "logging4.test" },
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "syslog",
        config   = {
          log_level              = "info",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "syslog",
        config   = {
          log_level              = "err",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "syslog",
        config   = {
          log_level              = "warning",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }

      bp.plugins:insert {
        route = { id = route4.id },
        name     = "syslog",
        config   = {
          log_level              = "warning",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
          custom_fields_by_lua = {
            new_field = "return 123",
            route = "return nil", -- unset route field
          },
        },
      }

      -- grpc [[
      local grpc_service = bp.services:insert {
        name = "grpc-service",
        url = helpers.grpcbin_url,
      }

      local grpc_route1 = bp.routes:insert {
        service = grpc_service,
        hosts = { "grpc_logging.test" },
      }

      local grpc_route2 = bp.routes:insert {
        service = grpc_service,
        hosts = { "grpc_logging2.test" },
      }

      local grpc_route3 = bp.routes:insert {
        service = grpc_service,
        hosts = { "grpc_logging3.test" },
      }

      bp.plugins:insert {
        route = { id = grpc_route1.id },
        name     = "syslog",
        config   = {
          log_level              = "info",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }

      bp.plugins:insert {
        route = { id = grpc_route2.id },
        name     = "syslog",
        config   = {
          log_level              = "err",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }

      bp.plugins:insert {
        route = { id = grpc_route3.id },
        name     = "syslog",
        config   = {
          log_level              = "warning",
          successful_severity    = "warning",
          client_errors_severity = "warning",
          server_errors_severity = "warning",
        },
      }
      -- grpc ]]

      local ok, _, stdout = helpers.execute("uname")
      assert(ok, "failed to retrieve platform name")
      platform = strip(stdout)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client_grpc = helpers.proxy_client_grpc()
    end)
    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = assert(helpers.proxy_client())
    end)
    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    local function do_test(host, expecting_same, grpc)
      local uuid = uuid.uuid()
      local ok, resp

      if not grpc then
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host         = host,
            sys_log_uuid = uuid,
          }
        })
        assert.res_status(200, response)

      else
        ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            [" -H"] = "'Content-Type: text/plain'",
            ["-H"] = "'sys_log_uuid: " .. uuid .. "'",
            ["-authority"] = ("%s"):format(host),
          }
        })
        assert.truthy(ok, resp)
        assert.truthy(resp)
      end

      if platform == "Darwin" then
        local _, _, stdout = assert(helpers.execute("syslog -k Sender kong | tail -1"))
        local msg  = string.match(stdout, "{.*}")
        local json = cjson.decode(msg)

        if expecting_same then
          assert.equal(uuid, json.request.headers["sys-log-uuid"])
        else
          assert.not_equal(uuid, json.request.headers["sys-log-uuid"])
        end

        resp = stdout
      elseif expecting_same then
        -- wait for file writing
        helpers.pwait_until(function()
          local _, _, stdout = assert(helpers.execute("sudo find /var/log -type f -mmin -5 | grep syslog"))
          assert.True(#stdout > 0)

          local files = split(stdout, "\n")
          assert.True(#files > 0)

          if files[#files] == "" then
            table.remove(files)
          end

          local tmp = {}

          -- filter out suspicious files
          for _, file in ipairs(files) do
            local _, stderr, stdout = assert(helpers.execute("file " .. file))

            assert(stdout, stderr)
            assert.True(#stdout > 0, stderr)

            --[[
              to avoid file like syslog.2.gz
              because syslog must be a text file
            --]]
            if stdout:find("text", 1, true) then
              table.insert(tmp, file)
            end
          end

          files = tmp

          local matched = false

          for _, file in ipairs(files) do
            --[[
              we have to run grep with sudo on Github Action 
              because of the `Permission denied` error
            -- ]]
            local cmd = string.format("sudo grep '\"sys_log_uuid\":\"%s\"' %s", uuid, file)
            local ok, _, stdout = helpers.execute(cmd)
            if ok then
              matched = true
              resp = stdout
              break
            end
          end

          assert(matched, "uuid not found in syslog")

        end, 5)
      end

      return resp
    end

    it("logs to syslog if log_level is lower", function()
      do_test("logging.test", true)
    end)
    it("does not log to syslog if log_level is higher", function()
      do_test("logging2.test", false)
    end)
    it("logs to syslog if log_level is the same", function()
      do_test("logging3.test", true)
    end)
    it("logs custom values", function()
      local resp = do_test("logging4.test", true)
      assert.matches("\"new_field\".*123", resp)
      assert.not_matches("\"route\"", resp)
    end)

    it("logs to syslog if log_level is lower #grpc", function()
      do_test("grpc_logging.test", true, true)
    end)
    it("does not log to syslog if log_level is higher #grpc", function()
      do_test("grpc_logging2.test", false, true)
    end)
    it("logs to syslog if log_level is the same #grpc", function()
      do_test("grpc_logging3.test", true, true)
    end)
  end)
end
