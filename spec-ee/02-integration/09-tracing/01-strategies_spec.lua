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


for _, strategy in helpers.each_strategy() do
describe("tracing [#" .. strategy .. "]", function()
  describe("file", function()
    local proxy_client, trace_log, trace_log_size

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
      }))

    end)

    teardown(function()
      helpers.stop_kong()
      os.remove(TRACE_LOG_PATH)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("writes traces to a file in file format", function()
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

      trace_log_size = pl_path.getsize(TRACE_LOG_PATH)

      trace_log = pl_file.read(TRACE_LOG_PATH)

      -- it's not written as a JSON blob
      assert.has_errors(function() cjson.decode(trace_log) end)

      -- it contains the human readable markers
      assert.matches(string.rep("=", 35), trace_log)

      -- it contains the router trace
      assert.matches("name: router", trace_log)

      -- it contains the access phase traces
      for _, phase in ipairs({"before", "after"}) do
        assert.match("name: access." .. phase, trace_log)
      end
    end)

    it("writes a second trace", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and
               pl_path.getsize(TRACE_LOG_PATH) > trace_log_size
      end, 10)

      assert.has_errors(function() cjson.decode(trace_log) end)
    end)

    it("writes a trace after the original file was removed", function()
      os.remove(TRACE_LOG_PATH)

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

      -- it's not written as a JSON blob
      assert.has_errors(function() cjson.decode(trace_log) end)

      -- it contains the human readable markers
      assert.matches(string.rep("=", 35), trace_log)

      -- it contains the router trace
      assert.matches("name: router", trace_log)

      -- it contains the access phase traces
      for _, phase in ipairs({"before", "after"}) do
        assert.match("name: access." .. phase, trace_log)
      end
    end)
  end)


  describe("file_raw", function()
    local proxy_client, trace_log, trace_log_size

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
      }))

    end)

    teardown(function()
      helpers.stop_kong()
      os.remove(TRACE_LOG_PATH)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("writes traces to a file in raw format", function()
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

      trace_log_size = pl_path.getsize(TRACE_LOG_PATH)
      trace_log = pl_file.read(TRACE_LOG_PATH)

      local traces = cjson.decode(trace_log)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      -- we have at least one db call
      -- this is the workspace scope lookup
      assert(has_trace_element(traces, "name", "query"))
    end)

    it("writes a second trace", function()
      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        return pl_path.exists(TRACE_LOG_PATH) and
               pl_path.getsize(TRACE_LOG_PATH) > trace_log_size
      end, 10)

      local f = assert(io.open(TRACE_LOG_PATH))
      local lines = f:read()

      local traces = cjson.decode(lines)
      lines = f:read()
      f:close()

      local second_traces = cjson.decode(lines)
      for _, trace in ipairs(second_traces) do
        table.insert(traces, trace)
      end

      local trace_requests, n = {}, 0
      for _, trace in ipairs(traces) do
        if not trace_requests[trace.request] then
          trace_requests[trace.request] = true
          n = n + 1
        end
      end
      assert.same(2, n)
    end)

    it("writes a trace after the original file was removed", function()
      os.remove(TRACE_LOG_PATH)

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

      assert(cjson.decode(trace_log))
    end)
  end)


  describe("tcp", function()
    local proxy_client

    local TCP_PORT = 35001

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = true,
        tracing_write_strategy = "tcp",
        tracing_write_endpoint = "127.0.0.1:" .. tostring(TCP_PORT),
      }))

    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("writes traces to a TCP socket", function()
      local thread = helpers.tcp_server(TCP_PORT)

      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- wait a bit for msg to be sent via timer
      ngx.sleep(0.3)

      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      local traces = cjson.decode(res)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      -- we have at least one db call
      -- this is the workspace scope lookup
      assert(has_trace_element(traces, "name", "query"))
    end)
  end)


  -- there seems to be a problem with TLS functionality in the mock tcp server
  pending("tls", function()
    local proxy_client

    local TCP_PORT = 35002

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = true,
        tracing_write_strategy = "tls",
        tracing_write_endpoint = "127.0.0.1:" .. tostring(TCP_PORT),
      }))

    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("writes traces to a TCP socket via TLS", function()
      local thread = helpers.tcp_server(TCP_PORT, { tls = true })

      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- wait a bit for msg to be sent via timer
      ngx.sleep(0.3)

      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      local traces = cjson.decode(res)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      -- we have at least one db call
      -- this is the workspace scope lookup
      assert(has_trace_element(traces, "name", "query"))
    end)
  end)

  describe("udp", function()
    local proxy_client

    local UDP_PORT = 35003

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = true,
        tracing_write_strategy = "udp",
        tracing_write_endpoint = "127.0.0.1:" .. tostring(UDP_PORT),
      }))

    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("writes traces to a UDP socket", function()
      local thread = helpers.udp_server(UDP_PORT)

      -- delay to let the mock UDP server start up
      ngx.sleep(2.5)

      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- wait a bit for msg to be sent via timer
      ngx.sleep(0.3)

      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      local traces = cjson.decode(res)

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      -- we have at least one db call
      -- this is the workspace scope lookup
      assert(has_trace_element(traces, "name", "query"))
    end)
  end)


  describe("http", function()
    local proxy_client

    local HTTP_PORT = 35004

    setup(function()
      local bp, _, _ = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "example.com" },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        tracing = true,
        tracing_write_strategy = "http",
        tracing_write_endpoint = "http://127.0.0.1:" .. tostring(HTTP_PORT),
      }))

    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    pending("writes traces to an HTTP server", function()
      local thread = helpers.http_server(HTTP_PORT)

      local res = assert(proxy_client:send({
        method = "GET",
        headers = {
          Host = "example.com",
        }
      }))
      assert.res_status(200, res)

      -- wait a bit for msg to be sent via timer
      ngx.sleep(0.3)

      local ok, res = thread:join()
      assert.True(ok)

      -- seventh index is the body
      local traces = cjson.decode(res[7])

      assert(has_trace_element(traces, "name", "router"))

      for _, phase in ipairs({"before", "after"}) do
        assert(has_trace_element(traces, "name", "access." .. phase))
      end

      -- we have at least one db call
      -- this is the workspace scope lookup
      assert(has_trace_element(traces, "name", "query"))
    end)
  end)
end)
end
