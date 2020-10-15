local cjson = require "cjson"
local declarative = require "kong.db.declarative"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local CONSISTENCY_FREQ = 0.1
local FIRST_PORT = 20000
local HEALTHCHECK_INTERVAL = 0.01
local SLOTS = 10
local TEST_LOG = false -- extra verbose logging of test server
local TIMEOUT = -1  -- marker for timeouts in http_server
local healthchecks_defaults = {
  active = {
    timeout = 1,
    concurrency = 10,
    http_path = "/",
    healthy = {
      interval = 0, -- 0 = disabled by default
      http_statuses = { 200, 302 },
      successes = 2,
    },
    unhealthy = {
      interval = 0, -- 0 = disabled by default
      http_statuses = { 429, 404,
                        500, 501, 502, 503, 504, 505 },
      tcp_failures = 2,
      timeouts = 3,
      http_failures = 5,
    },
  },
  passive = {
    healthy = {
      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                        300, 301, 302, 303, 304, 305, 306, 307, 308 },
      successes = 5,
    },
    unhealthy = {
      http_statuses = { 429, 500, 503 },
      tcp_failures = 2,
      timeouts = 7,
      http_failures = 5,
    },
  },
}


local prefix = ""


local function healthchecks_config(config)
  return utils.deep_merge(healthchecks_defaults, config)
end


local function direct_request(host, port, path, protocol, host_header)
  local pok, client = pcall(helpers.http_client, host, port)
  if not pok then
    return nil, "pcall: " .. client .. " : " .. host ..":"..port
  end
  if not client then
    return nil, "client"
  end

  if protocol == "https" then
    assert(client:ssl_handshake())
  end

  local res, err = client:send {
    method = "GET",
    path = path,
    headers = { ["Host"] = host_header or host }
  }
  local body = res and res:read_body()
  client:close()
  if err then
    return nil, err
  end
  return body
end


local function post_target_endpoint(upstream_id, host, port, endpoint)
  local path = "/upstreams/" .. upstream_id
                             .. "/targets/"
                             .. utils.format_host(host, port)
                             .. "/" .. endpoint
  local api_client = helpers.admin_client()
  local res, err = assert(api_client:send {
    method = "POST",
    path = prefix .. path,
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = {},
  })
  api_client:close()
  return res, err
end


-- Modified http-server. Accepts (sequentially) a number of incoming
-- connections and then rejects a given number of connections.
-- @param host Host name to use (IPv4 or IPv6 localhost).
-- @param port Port number to use.
-- @param counts Array of response counts to give,
-- odd entries are 200s, event entries are 500s
-- @param test_log (optional, default fals) Produce detailed logs
-- @return Returns the number of successful and failure responses.
local function http_server(host, port, counts, test_log, protocol, check_hostname)
  -- This is a "hard limit" for the execution of tests that launch
  -- the custom http_server
  local hard_timeout = ngx.now() + 300
  protocol = protocol or "http"

  local cmd = "resty --errlog-level error " .. -- silence _G write guard warns
              "spec/fixtures/balancer_https_server.lua " ..
              protocol .. " " .. host .. " " .. port ..
              " \"" .. cjson.encode(counts):gsub('"', '\\"') .. "\" " ..
              (test_log or "false") .. " ".. (check_hostname or "false") .. " &"
  os.execute(cmd)

  repeat
    local _, err = direct_request(host, port, "/handshake", protocol)
    if err then
      ngx.sleep(0.01) -- poll-wait
    end
  until (ngx.now() > hard_timeout) or not err

  local server = {}
  server.done = function(_, host_header)
    local body = direct_request(host, port, "/shutdown", protocol, host_header)
    if body then
      local tbl = assert(cjson.decode(body))
      return true, tbl.ok_responses, tbl.fail_responses, tbl.n_checks
    end
  end

  return server
end


local function client_requests(n, host_or_headers, proxy_host, proxy_port, protocol)
  local oks, fails = 0, 0
  local last_status
  for _ = 1, n do
    local client = (proxy_host and proxy_port)
                   and helpers.http_client(proxy_host, proxy_port)
                   or  helpers.proxy_client()

    if protocol == "https" then
      assert(client:ssl_handshake())
    end

    local res = client:send {
      method = "GET",
      path = "/",
      headers = type(host_or_headers) == "string"
                and { ["Host"] = host_or_headers }
                or host_or_headers
                or {}
    }
    if not res then
      fails = fails + 1
      if TEST_LOG then
        print("FAIL (no body)")
      end
    elseif res.status == 200 then
      oks = oks + 1
      if TEST_LOG then
        print("OK ", res.status, res:read_body())
      end
    elseif res.status > 399 then
      fails = fails + 1
      if TEST_LOG then
        print("FAIL ", res.status, res:read_body())
      end
    end
    last_status = res and res.status
    client:close()
  end
  return oks, fails, last_status
end


local add_upstream
local remove_upstream
local patch_upstream
local get_upstream
local get_upstream_health
local get_balancer_health
local post_target_address_health
local get_router_version
local add_target
local update_target
local add_api
local patch_api
local gen_port
local gen_multi_host
local invalidate_router
do
  local gen_sym
  do
    local sym = 0
    gen_sym = function(name)
      sym = sym + 1
      return name .. "_" .. sym
    end
  end

  local function api_send(method, path, body, forced_port)
    local api_client = helpers.admin_client(nil, forced_port)
    local res, err = api_client:send({
      method = method,
      path = prefix .. path,
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = body,
    })
    if not res then
      api_client:close()
      return nil, err
    end
    local res_body = res.status ~= 204 and cjson.decode((res:read_body()))
    api_client:close()
    return res.status, res_body
  end

  add_upstream = function(bp, data)
    local upstream_id = utils.uuid()
    local req = utils.deep_copy(data) or {}
    local upstream_name = req.name or gen_sym("upstream")
    req.name = upstream_name
    req.slots = req.slots or SLOTS
    req.id = upstream_id
    bp.upstreams:insert(req)
    return upstream_name, upstream_id
  end

  remove_upstream = function(bp, upstream_id)
    bp.upstreams:remove({ id = upstream_id })
  end

  patch_upstream = function(upstream_id, data)
    local res = api_send("PATCH", "/upstreams/" .. upstream_id, data)
    assert(res == 200)
  end

  get_upstream = function(upstream_id, forced_port)
    local path = "/upstreams/" .. upstream_id
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body
    end
  end

  get_upstream_health = function(upstream_id, forced_port)
    local path = "/upstreams/" .. upstream_id .."/health"
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body
    end
  end

  get_balancer_health = function(upstream_id, forced_port)
    local path = "/upstreams/" .. upstream_id .."/health?balancer_health=1"
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body
    end
  end

  post_target_address_health = function(upstream_id, target_id, address, mode, forced_port)
    local path = "/upstreams/" .. upstream_id .. "/targets/" .. target_id .. "/" .. address .. "/" .. mode
    return api_send("POST", path, {}, forced_port)
  end

  get_router_version = function(forced_port)
    local path = "/cache/router:version"
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body.message
    end
  end

  invalidate_router = function(forced_port)
    local path = "/cache/router:version"
    local status, body = api_send("DELETE", path, nil, forced_port)
    if status == 204 then
      return true
    end

    return nil, body
  end

  do
    local os_name
    do
      local pd = io.popen("uname -s")
      os_name = pd:read("*l")
      pd:close()
    end
    local function port_in_use(port)
      if os_name ~= "Linux" then
        return false
      end
      return os.execute("netstat -n | grep -q -w " .. port)
    end

    local port = FIRST_PORT
    gen_port = function()
      repeat
        port = port + 1
      until not port_in_use(port)
      return port
    end
  end

  do
    local host_num = 0
    gen_multi_host = function()
      host_num = host_num + 1
      return "multiple-hosts-" .. tostring(host_num) .. ".test"
    end
  end

  add_target = function(bp, upstream_id, host, port, data)
    port = port or gen_port()
    local req = utils.deep_copy(data) or {}
    req.target = req.target or utils.format_host(host, port)
    req.weight = req.weight or 10
    req.upstream = { id = upstream_id }
    local new_target = bp.targets:insert(req)
    return port, new_target
  end

  update_target = function(bp, upstream_id, host, port, data)
    local req = utils.deep_copy(data) or {}
    req.target = req.target or utils.format_host(host, port)
    req.weight = req.weight or 10
    req.upstream = { id = upstream_id }
    bp.targets:update(req.id or req.target, req)
  end

  add_api = function(bp, upstream_name, opts)
    opts = opts or {}
    local route_id = utils.uuid()
    local service_id = utils.uuid()
    local route_host = gen_sym("host")
    local sproto = opts.service_protocol or opts.route_protocol or "http"
    local rproto = opts.route_protocol or "http"

    bp.services:insert({
      id = service_id,
      url = sproto .. "://" .. upstream_name .. ":" .. (rproto == "tcp" and 9100 or 80),
      read_timeout = opts.read_timeout,
      write_timeout = opts.write_timeout,
      connect_timeout = opts.connect_timeout,
      retries = opts.retries,
      protocol = sproto,
    })
    bp.routes:insert({
      id = route_id,
      service = { id = service_id },
      protocols = { rproto },
      hosts = rproto ~= "tcp" and { route_host } or nil,
      destinations = (rproto == "tcp") and {{ port = 9100 }} or nil,
    })
    return route_host, service_id, route_id
  end

  patch_api = function(bp, service_id, new_upstream, read_timeout)
    bp.services:update(service_id, {
      url = new_upstream,
      read_timeout = read_timeout,
    })
  end
end


local poll_wait_health
local poll_wait_address_health
do
  local function poll_wait(upstream_id, host, port, admin_port, fn)
    local hard_timeout = ngx.now() + 70
    while ngx.now() < hard_timeout do
      local health = get_upstream_health(upstream_id, admin_port)
      if health then
        for _, d in ipairs(health.data) do
          if d.target == host .. ":" .. port and fn(d) then
            return true
          end
        end
      end
      ngx.sleep(0.1) -- poll-wait
    end
    return false
  end

  poll_wait_health = function(upstream_id, host, port, value, admin_port)
    local ok = poll_wait(upstream_id, host, port, admin_port, function(d)
          return d.health == value
    end)
    if ok then
      return true
    end
    assert(false, "timed out waiting for " .. host .. ":" .. port .. " in " ..
                      upstream_id .. " to become " .. value)
                        end

  poll_wait_address_health = function(upstream_id, host, port, address_host, address_port, value)
    local ok = poll_wait(upstream_id, host, port, nil, function(d)
      for _, ad in ipairs(d.data.addresses) do
        if ad.ip == address_host
        and ad.port == address_port
        and ad.health == value then
          return true
        end
      end
    end)
    if ok then
      return true
    end
    assert(false, "timed out waiting for " .. address_host .. ":" .. address_port .. " in " ..
                      upstream_id .. " to become " .. value)
  end
end


local function wait_for_router_update(bp, old_rv, localhost, proxy_port, admin_port)
  -- add dummy upstream just to rebuild router
  local dummy_upstream_name, dummy_upstream_id = add_upstream(bp)
  local dummy_port = add_target(bp, dummy_upstream_id, localhost)
  local dummy_api_host = add_api(bp, dummy_upstream_name)
  local dummy_server = http_server(localhost, dummy_port, { 1000 })

  -- forces the router to be rebuild, reduces the flakiness of the test suite
  -- TODO: find out what's wrong with router invalidation in the particular
  -- test setup causing the flakiness
  assert(invalidate_router(admin_port))

  helpers.wait_until(function()
    client_requests(1, dummy_api_host, "127.0.0.1", proxy_port)
    local rv = get_router_version(admin_port)
    return rv ~= old_rv
  end, 5)

  dummy_server:done()
end


local function tcp_client_requests(nreqs, host, port)
  local fails, ok1, ok2 = 0, 0, 0
  for _ = 1, nreqs do
    local sock = ngx.socket.tcp()
    assert(sock:connect(host, port))
    assert(sock:send("hello\n"))
    local response, err = sock:receive()
    if err then
      fails = fails + 1
    elseif response:match("^1 ") then
      ok1 = ok1 + 1
    elseif response:match("^2 ") then
      ok2 = ok2 + 1
    end
  end
  return ok1, ok2, fails
end


local function begin_testcase_setup(strategy, bp)
  if strategy == "off" then
    bp.done()
  end
end

local function begin_testcase_setup_update(strategy, bp)
  if strategy == "off" then
    bp.reset_back()
  end
end


local function end_testcase_setup(strategy, bp, consistency)
  if strategy == "off" then
    local cfg = bp.done()
    local yaml = declarative.to_yaml_string(cfg)
    local admin_client = helpers.admin_client()
    local res = assert(admin_client:send {
      method  = "POST",
      path    = "/config",
      body    = {
        config = yaml,
      },
      headers = {
        ["Content-Type"] = "multipart/form-data",
      }
    })
    assert(res ~= nil)
    assert(res.status == 201)
    admin_client:close()
  end
  if consistency == "eventual" then
    ngx.sleep(CONSISTENCY_FREQ*2) -- wait for proxy state consistency timer
  end
end


local function get_db_utils_for_dc_and_admin_api(strategy, tables)
  local bp = assert(helpers.get_db_utils(strategy, tables))
  if strategy ~= "off" then
    bp = require("spec.fixtures.admin_api")
  end
  return bp
end


local function setup_prefix(p)
  prefix = p
  local bp = require("spec.fixtures.admin_api")
  bp.set_prefix(prefix)
end


local function teardown_prefix()
  prefix = ""
  local bp = require("spec.fixtures.admin_api")
  bp.set_prefix(prefix)
end


local function test_with_prefixes(_it, strategy, prefixes)
  return function(description, fn)
    if strategy == "off" then
      _it(description, fn)
      return
    end

    for _, name in ipairs(prefixes) do
      _it(name .. ": " .. description, function()
        setup_prefix("/" .. name)
        local ok = fn()
        teardown_prefix()
        return ok
      end)
    end
  end
end


local localhosts = {
  ipv4 = "127.0.0.1",
  ipv6 = "[0000:0000:0000:0000:0000:0000:0000:0001]",
  hostname = "localhost",
}


local consistencies = {"strict", "eventual"}


local balancer_utils = {}
--balancer_utils.
balancer_utils.add_api = add_api
balancer_utils.add_target = add_target
balancer_utils.update_target = update_target
balancer_utils.add_upstream = add_upstream
balancer_utils.remove_upstream = remove_upstream
balancer_utils.begin_testcase_setup = begin_testcase_setup
balancer_utils.begin_testcase_setup_update = begin_testcase_setup_update
balancer_utils.client_requests = client_requests
balancer_utils.consistencies = consistencies
balancer_utils.CONSISTENCY_FREQ = CONSISTENCY_FREQ
balancer_utils.direct_request = direct_request
balancer_utils.end_testcase_setup = end_testcase_setup
balancer_utils.gen_multi_host = gen_multi_host
balancer_utils.gen_port = gen_port
balancer_utils.get_balancer_health = get_balancer_health
balancer_utils.get_db_utils_for_dc_and_admin_api = get_db_utils_for_dc_and_admin_api
balancer_utils.get_router_version = get_router_version
balancer_utils.get_upstream = get_upstream
balancer_utils.get_upstream_health = get_upstream_health
balancer_utils.healthchecks_config = healthchecks_config
balancer_utils.HEALTHCHECK_INTERVAL = HEALTHCHECK_INTERVAL
balancer_utils.http_server = http_server
balancer_utils.localhosts = localhosts
balancer_utils.patch_api = patch_api
balancer_utils.patch_upstream = patch_upstream
balancer_utils.poll_wait_address_health = poll_wait_address_health
balancer_utils.poll_wait_health = poll_wait_health
balancer_utils.post_target_address_health = post_target_address_health
balancer_utils.post_target_endpoint = post_target_endpoint
balancer_utils.SLOTS = SLOTS
balancer_utils.tcp_client_requests = tcp_client_requests
balancer_utils.TIMEOUT = TIMEOUT
balancer_utils.wait_for_router_update = wait_for_router_update
balancer_utils.test_with_prefixes = test_with_prefixes


return balancer_utils
