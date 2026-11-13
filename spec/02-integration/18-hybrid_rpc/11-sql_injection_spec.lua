-- NOTE: This test suite validates SQL injection protection and input validation
-- for Kong Hybrid Mode RPC connections. It tests node_id (UUID) and hostname
-- validation.

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local uuid = require("kong.tools.uuid").uuid
local ssl = require "ngx.ssl"
local pl_file = require "pl.file"
local ws_client = require "resty.websocket.client"
local ngx_escape_uri = ngx.escape_uri


local CLUSTER_PORT = 9005
local CLUSTER_SSL_PORT = 9005


local function get_cp_env(strategy)
  return {
    role = "control_plane",
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    database = strategy,
    cluster_listen = "127.0.0.1:" .. CLUSTER_PORT,
    nginx_conf = "spec/fixtures/custom_nginx.template",
    plugins = "bundled",
    nginx_worker_processes = 4,
    cluster_rpc = "on",
  }
end


-- Helper to create WebSocket connection options
local function get_ws_opts()
  return {
    ssl_verify = false,
    client_cert = assert(ssl.parse_pem_cert(assert(pl_file.read("spec/fixtures/kong_clustering.crt")))),
    client_priv_key = assert(ssl.parse_pem_priv_key(assert(pl_file.read("spec/fixtures/kong_clustering.key")))),
    server_name = "kong_clustering",
  }
end


-- Helper to connect to v1/outlet with a custom node_id
local function connect_v1_outlet(node_id, node_hostname, node_version)
  local c = assert(ws_client:new())
  -- URL encode parameters to ensure special characters are transmitted correctly
  local encoded_node_id = ngx_escape_uri(node_id or uuid())
  local encoded_hostname = ngx_escape_uri(node_hostname or "test-node")
  local uri = "wss://127.0.0.1:" .. CLUSTER_SSL_PORT ..
              "/v1/outlet?node_id=" .. encoded_node_id ..
              "&node_hostname=" .. encoded_hostname ..
              "&node_version=" .. (node_version or "3.14.0")

  local ok, err = c:connect(uri, get_ws_opts())
  return c, ok, err
end


-- Helper to connect to v2/outlet and send RPC handshake with custom node_id and hostname
local function connect_v2_outlet_with_handshake(node_id, hostname)
  local c = assert(ws_client:new())
  local uri = "wss://127.0.0.1:" .. CLUSTER_SSL_PORT .. "/v2/outlet"

  local opts = get_ws_opts()
  opts.protocols = "kong.meta.v1"

  local ok, err = c:connect(uri, opts)
  if not ok then
    return nil, nil, err
  end

  -- Send the RPC handshake with potentially malicious node_id or hostname
  local handshake = {
    jsonrpc = "2.0",
    method = "kong.meta.v1.hello",
    params = {{
      kong_version = "3.14.0",
      kong_node_id = node_id or uuid(),
      kong_hostname = hostname or "test-node",
      kong_conf = {},
      rpc_capabilities = {},
      rpc_frame_encodings = { "x-snappy-framed" },
    }},
    id = 1,
  }

  local bytes, err = c:send_binary(cjson.encode(handshake))
  if not bytes then
    c:close()
    return nil, nil, err
  end

  -- Try to receive response
  c:set_timeout(3000)
  local data, typ, recv_err = c:recv_frame()

  return c, { data = data, typ = typ }, recv_err
end


for _, strategy in helpers.each_strategy() do
describe("SQL Injection Protection #" .. strategy, function()
  -- Default prefix is "servroot"
  local cp_logfile = "servroot/logs/error.log"

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "clustering_data_planes",
    })

    local cp_env = get_cp_env(strategy)
    assert(helpers.start_kong(cp_env))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("v1/outlet (control_plane.handle_cp_websocket)", function()
    it("rejects connection with SQL injection payload in node_id", function()
      -- SQL injection payload attempting to break out of identifier
      local malicious_id = 'x"; SELECT pg_sleep(5); --'
      local c, ok, _ = connect_v1_outlet(malicious_id)

      -- Connection should be rejected or closed immediately
      if ok then
        -- If connected, try to receive - should get close frame
        c:set_timeout(1000)
        local _, typ = c:recv_frame()
        c:close()
        -- Should receive close frame or connection should fail
        assert.is_true(typ == "close" or typ == nil,
          "Connection with malicious node_id should be rejected")
      end

      -- Check logs for the rejection message
      assert.logfile(cp_logfile).has.line(
        "invalid node_id format, must be a valid UUID", true, 5)
    end)

    it("rejects connection with non-UUID node_id", function()
      local invalid_ids = {
        "not-a-uuid",
        "12345",
        "",
        "DROP TABLE clustering_data_planes;",
        "../../../etc/passwd",
      }

      for _, invalid_id in ipairs(invalid_ids) do
        helpers.clean_logfile(cp_logfile)

        local c, ok = connect_v1_outlet(invalid_id)
        if ok then
          c:set_timeout(500)
          local _, typ = c:recv_frame()
          c:close()
          -- Should receive close frame indicating rejection
          assert.is_true(typ == "close" or typ == nil,
            "Connection with invalid node_id '" .. invalid_id .. "' should be rejected")
        end
        -- If ok is false, connection was rejected at handshake level, which is also correct

        -- Verify log message for this specific invalid input
        assert.logfile(cp_logfile).has.line(
          "invalid node_id format, must be a valid UUID", true, 5)
      end
    end)

    it("accepts connection with valid UUID node_id", function()
      local valid_uuid = uuid()
      local c, ok, err = connect_v1_outlet(valid_uuid)

      assert.is_truthy(ok, "Connection with valid UUID should succeed: " .. (err or ""))

      if ok then
        -- Send basic_info to complete handshake
        local payload = cjson.encode({
          type = "basic_info",
          plugins = {},
        })
        c:send_binary(payload)
        c:close()
      end

      -- Should not see rejection message for valid UUID
      -- (We can't easily assert absence, but the connection succeeding is enough)
    end)

    it("rejects connection with invalid hostname format", function()
      local valid_uuid = uuid()
      -- Focus on security-relevant invalid hostnames
      -- Note: underscores are allowed because gethostname() may return them
      local invalid_hostnames = {
        'host"; DROP TABLE test; --',   -- SQL injection
        "../../../etc/passwd",          -- path traversal
        "host\nname",                   -- newline injection
        "host name",                    -- space injection
        "host..name",                   -- consecutive dots
        "host-.name",                   -- label ends with hyphen
      }

      for _, invalid_hostname in ipairs(invalid_hostnames) do
        helpers.clean_logfile(cp_logfile)

        local c, ok = connect_v1_outlet(valid_uuid, invalid_hostname)
        if ok then
          c:set_timeout(500)
          local _, typ = c:recv_frame()
          c:close()
          -- Should receive close frame indicating rejection
          assert.is_true(typ == "close" or typ == nil,
            "Connection with invalid hostname '" .. invalid_hostname .. "' should be rejected")
        end
        -- If ok is false, connection was rejected at handshake level, which is also correct

        -- Verify log message for this specific invalid input
        assert.logfile(cp_logfile).has.line(
          "invalid hostname format", true, 5)
      end
    end)

    it("accepts connection with valid hostname format", function()
      local valid_uuid = uuid()
      -- Representative valid hostnames (including underscore for gethostname() compatibility)
      local valid_hostnames = {
        "simple-host",                  -- simple hostname with hyphen
        "host.example.com",             -- FQDN
        "host-123.example-456.com",     -- complex FQDN
        "my_server_01",                 -- underscore (allowed by Linux gethostname)
      }

      for _, valid_hostname in ipairs(valid_hostnames) do
        local c, ok, err = connect_v1_outlet(valid_uuid, valid_hostname)
        assert.is_truthy(ok, "Connection with valid hostname '" .. valid_hostname .. "' should succeed: " .. (err or ""))
        if ok then
          c:close()
        end
      end
    end)
  end)

  describe("v2/outlet (rpc.manager._handle_meta_call)", function()
    it("rejects handshake with SQL injection payload in kong_node_id", function()
      local malicious_id = 'x"; DROP TABLE clustering_rpc_requests; --'
      local c, _, _ = connect_v2_outlet_with_handshake(malicious_id)

      if c then
        c:close()
      end

      -- Check logs for the rejection message
      assert.logfile(cp_logfile).has.line(
        "invalid node_id format, must be a valid UUID", true, 5)
    end)

    it("rejects handshake with time-based SQL injection payload", function()
      local malicious_id = 'x"; SELECT pg_sleep(10); --'
      local start_time = ngx.now()
      local c, _, _ = connect_v2_outlet_with_handshake(malicious_id)
      local elapsed = ngx.now() - start_time

      if c then
        c:close()
      end

      -- If SQL injection worked, it would take ~10 seconds
      -- With protection, it should be rejected quickly
      assert.is_true(elapsed < 5,
        "Request should be rejected quickly, not delayed by SQL injection. Elapsed: " .. elapsed)

      assert.logfile(cp_logfile).has.line(
        "invalid node_id format, must be a valid UUID", true, 5)
    end)

    it("accepts handshake with valid UUID kong_node_id", function()
      local valid_uuid = uuid()
      local c, response, err = connect_v2_outlet_with_handshake(valid_uuid)

      -- Should receive a valid response (not an error)
      assert.is_truthy(c, "Connection should succeed: " .. (err or ""))

      if response and response.data then
        local resp = cjson.decode(response.data)
        -- Should get a valid JSON-RPC response
        assert.is_truthy(resp, "Should receive valid JSON response")
        if resp then
          assert.equals("2.0", resp.jsonrpc)
          assert.is_truthy(resp.result, "Should have result, not error")
        end
      end

      if c then
        c:close()
      end
    end)

    it("rejects handshake with invalid hostname format", function()
      local valid_uuid = uuid()
      -- Focus on security-relevant invalid hostnames
      -- Note: underscores are allowed because gethostname() may return them
      local invalid_hostnames = {
        'host"; DROP TABLE test; --',   -- SQL injection
        "../../../etc/passwd",          -- path traversal
        "host name",                    -- space injection
        "host..name",                   -- consecutive dots
        "host-.name",                   -- label ends with hyphen
      }

      for _, invalid_hostname in ipairs(invalid_hostnames) do
        helpers.clean_logfile(cp_logfile)

        local c, response, _ = connect_v2_outlet_with_handshake(valid_uuid, invalid_hostname)
        if c then
          -- Check if we got an error response or connection was closed
          if response and response.data then
            local resp = cjson.decode(response.data)
            -- Should get an error, not a successful result
            assert.is_true(resp == nil or resp.error ~= nil or response.typ == "close",
              "Handshake with invalid hostname '" .. invalid_hostname .. "' should be rejected")
          end
          c:close()
        end
        -- If c is nil, connection/handshake was rejected, which is correct

        -- Verify log message for this specific invalid input
        assert.logfile(cp_logfile).has.line(
          "invalid hostname format", true, 5)
      end
    end)

    it("accepts handshake with valid hostname format", function()
      local valid_uuid = uuid()
      -- Representative valid hostnames (including underscore for gethostname() compatibility)
      local valid_hostnames = {
        "simple-host",                  -- simple hostname with hyphen
        "host.example.com",             -- FQDN
        "my_server_01",                 -- underscore (allowed by Linux gethostname)
      }

      for _, valid_hostname in ipairs(valid_hostnames) do
        local c, response, err = connect_v2_outlet_with_handshake(valid_uuid, valid_hostname)
        assert.is_truthy(c, "Connection with valid hostname '" .. valid_hostname .. "' should succeed: " .. (err or ""))

        if response and response.data then
          local resp = cjson.decode(response.data)
          assert.is_truthy(resp and resp.result, "Should have valid result for hostname: " .. valid_hostname)
        end

        if c then
          c:close()
        end
      end
    end)
  end)
end)
end -- for _, strategy
