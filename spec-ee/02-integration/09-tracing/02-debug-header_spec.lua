local helpers = require "spec.helpers"
local pl_path = require "pl.path"


local TRACE_LOG_PATH = os.tmpname()


for _, strategy in helpers.each_strategy() do
describe("tracing [#" .. strategy .. "]", function()
  describe("debug header", function()
    local proxy_client

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      os.remove(TRACE_LOG_PATH)

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = true,
        tracing_write_strategy = "file",
        tracing_write_endpoint = TRACE_LOG_PATH,
        tracing_debug_header = "X-Kong-Debug",
      }))

    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      helpers.stop_kong()
      os.remove(TRACE_LOG_PATH)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      os.remove(TRACE_LOG_PATH)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("generates a trace when the debug header is present", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
          ["X-Kong-Debug"] = "yassss",
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and pl_path.getsize(TRACE_LOG_PATH) > 0
      end, 10)
    end)

    it("generates a trace when the debug header is present multiple times", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
          ["X-Kong-Debug"] = { "yassss", "queen" }
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and pl_path.getsize(TRACE_LOG_PATH) > 0
      end, 10)
    end)

    it("does not generate a trace when the debug header is not present", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- sleep a bit to wait for trace to 'potentially' be written
      ngx.sleep(1)

      assert(not pl_path.exists(TRACE_LOG_PATH))
    end)
  end)

  describe("debug header without tracing enabled", function()
    local proxy_client

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      os.remove(TRACE_LOG_PATH)

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = false,
        tracing_write_strategy = "file",
        tracing_write_endpoint = TRACE_LOG_PATH,
        tracing_debug_header = "X-Kong-Debug",
      }))

    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      helpers.stop_kong()
      os.remove(TRACE_LOG_PATH)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      os.remove(TRACE_LOG_PATH)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("does not generate a trace when the debug header is present", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
          ["X-Kong-Debug"] = "yassss",
        }
      }))
      assert.res_status(200, res)

      -- sleep a bit to wait for trace to 'potentially' be written
      ngx.sleep(1)

      assert(not pl_path.exists(TRACE_LOG_PATH))
    end)

    it("does not generate a trace when the debug header is present multiple times", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
          ["X-Kong-Debug"] = { "yassss", "queen" }
        }
      }))
      assert.res_status(200, res)

      -- sleep a bit to wait for trace to 'potentially' be written
      ngx.sleep(1)

      assert(not pl_path.exists(TRACE_LOG_PATH))
    end)

    it("does not generate a trace when the debug header is not present", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- sleep a bit to wait for trace to 'potentially' be written
      ngx.sleep(1)

      assert(not pl_path.exists(TRACE_LOG_PATH))
    end)
  end)
end)
end
