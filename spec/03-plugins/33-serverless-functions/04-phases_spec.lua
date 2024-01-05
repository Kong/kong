local helpers = require "spec.helpers"

local mock_one_fn = [[
  local plugin_name = "%s"
  local filename = "/tmp/" .. plugin_name .. "_output"
  local text = "phase: '%s', index: '%s', plugin: '" .. plugin_name .. "'\n"
  local readfile = require("pl.utils").readfile
  local writefile = require("pl.utils").writefile

  return function()
      local file_content, err = readfile(filename) or ""
      file_content = file_content .. text
      assert(writefile(filename, file_content))
    end
]]


for _, plugin_name in ipairs({ "pre-function", "post-function" }) do

  -- This whole test is marked as pending because it relies on a side-effect (writing to a file)
  -- which is no longer a possibility after sandboxing
  pending("Plugin: " .. plugin_name, function()

    setup(function()
      local bp, db = helpers.get_db_utils()

      assert(db:truncate())

      local service = bp.services:insert {
        name     = "service-1",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      bp.routes:insert {
        service = { id = service.id },
        hosts   = { "one." .. plugin_name .. ".test" },
      }

      local config = {}
      for _, phase in ipairs({ "certificate", "rewrite", "access",
                               "header_filter", "body_filter", "log"}) do
        config[phase] = {}
        for i, index in ipairs({"first", "second", "third"}) do
          config[phase][i] = mock_one_fn:format(plugin_name, phase, index)
        end
      end

      bp.plugins:insert {
        name    = plugin_name,
        config  = config,
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)


    it("hits all phases, with 3 functions, on 3 requests", function()
      local filename = "/tmp/" .. plugin_name .. "_output"
      os.remove(filename)

      for i = 1,3 do
        local client = helpers.proxy_ssl_client()

        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "one." .. plugin_name .. ".test"
          }
        })
        assert.response(res).has.status(200)

        client:close()
        ngx.sleep(0.1) -- wait for log-phase handler to execute
      end

      local content = require("pl.utils").readfile(filename)
      assert.equal(([[
phase: 'certificate', index: 'first', plugin: 'pre-function'
phase: 'certificate', index: 'second', plugin: 'pre-function'
phase: 'certificate', index: 'third', plugin: 'pre-function'
phase: 'rewrite', index: 'first', plugin: 'pre-function'
phase: 'rewrite', index: 'second', plugin: 'pre-function'
phase: 'rewrite', index: 'third', plugin: 'pre-function'
phase: 'access', index: 'first', plugin: 'pre-function'
phase: 'access', index: 'second', plugin: 'pre-function'
phase: 'access', index: 'third', plugin: 'pre-function'
phase: 'header_filter', index: 'first', plugin: 'pre-function'
phase: 'header_filter', index: 'second', plugin: 'pre-function'
phase: 'header_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'log', index: 'first', plugin: 'pre-function'
phase: 'log', index: 'second', plugin: 'pre-function'
phase: 'log', index: 'third', plugin: 'pre-function'
phase: 'certificate', index: 'first', plugin: 'pre-function'
phase: 'certificate', index: 'second', plugin: 'pre-function'
phase: 'certificate', index: 'third', plugin: 'pre-function'
phase: 'rewrite', index: 'first', plugin: 'pre-function'
phase: 'rewrite', index: 'second', plugin: 'pre-function'
phase: 'rewrite', index: 'third', plugin: 'pre-function'
phase: 'access', index: 'first', plugin: 'pre-function'
phase: 'access', index: 'second', plugin: 'pre-function'
phase: 'access', index: 'third', plugin: 'pre-function'
phase: 'header_filter', index: 'first', plugin: 'pre-function'
phase: 'header_filter', index: 'second', plugin: 'pre-function'
phase: 'header_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'log', index: 'first', plugin: 'pre-function'
phase: 'log', index: 'second', plugin: 'pre-function'
phase: 'log', index: 'third', plugin: 'pre-function'
phase: 'certificate', index: 'first', plugin: 'pre-function'
phase: 'certificate', index: 'second', plugin: 'pre-function'
phase: 'certificate', index: 'third', plugin: 'pre-function'
phase: 'rewrite', index: 'first', plugin: 'pre-function'
phase: 'rewrite', index: 'second', plugin: 'pre-function'
phase: 'rewrite', index: 'third', plugin: 'pre-function'
phase: 'access', index: 'first', plugin: 'pre-function'
phase: 'access', index: 'second', plugin: 'pre-function'
phase: 'access', index: 'third', plugin: 'pre-function'
phase: 'header_filter', index: 'first', plugin: 'pre-function'
phase: 'header_filter', index: 'second', plugin: 'pre-function'
phase: 'header_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'body_filter', index: 'first', plugin: 'pre-function'
phase: 'body_filter', index: 'second', plugin: 'pre-function'
phase: 'body_filter', index: 'third', plugin: 'pre-function'
phase: 'log', index: 'first', plugin: 'pre-function'
phase: 'log', index: 'second', plugin: 'pre-function'
phase: 'log', index: 'third', plugin: 'pre-function'
]]):gsub("pre%-function", plugin_name),content)
    end)
  end)
end
