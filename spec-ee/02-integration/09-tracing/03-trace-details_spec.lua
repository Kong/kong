local cjson   = require "cjson"
local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


local TRACE_LOG_PATH = os.tmpname()


local function has_trace_element(traces, k, v)
  for _, trace in ipairs(traces) do
    if trace[k] == v then
      return true
    end
  end
end


local function has_trace_data(traces, k, name)
  for _, trace in ipairs(traces) do
    if trace.name == name then
      if trace.data[k] then
        return true
      end
    end
  end
end


for _, strategy in helpers.each_strategy() do
describe("tracing [#" .. strategy .. "] details", function()
  describe("enabled", function()
    local proxy_client, trace_log

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
        tracing_write_strategy = "file_raw",
        tracing_write_endpoint = TRACE_LOG_PATH,
        generate_trace_details = true,
      }))

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

    it("writes traces with context-specific data", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and pl_path.getsize(TRACE_LOG_PATH) > 0
      end, 10)

      trace_log = pl_file.read(TRACE_LOG_PATH)

      local traces = cjson.decode(trace_log)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      assert(has_trace_element(traces, "name", "query"))
      assert(has_trace_data(traces, "traceback", "query"))
      assert(has_trace_data(traces, "query", "query"))
    end)
  end)

  describe("disabled", function()
    local proxy_client, trace_log

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
        tracing_write_strategy = "file_raw",
        tracing_write_endpoint = TRACE_LOG_PATH,
        generate_trace_details = false,
      }))

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

    it("does not write traces with context-specific data", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and pl_path.getsize(TRACE_LOG_PATH) > 0
      end, 10)

      trace_log = pl_file.read(TRACE_LOG_PATH)

      local traces = cjson.decode(trace_log)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      for _, trace in ipairs(traces) do
        assert.is_nil(trace.data)
      end
    end)
  end)
end)
end
