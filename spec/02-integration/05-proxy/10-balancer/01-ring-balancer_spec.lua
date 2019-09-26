-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local declarative = require "kong.db.declarative"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local FIRST_PORT = 20000
local SLOTS = 10
local HEALTHCHECK_INTERVAL = 0.01

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


local function healthchecks_config(config)
  return utils.deep_merge(healthchecks_defaults, config)
end


local TEST_LOG = false -- extra verbose logging of test server


local TIMEOUT = -1  -- marker for timeouts in http_server


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
  local url = "/upstreams/" .. upstream_id
                            .. "/targets/"
                            .. utils.format_host(host, port)
                            .. "/" .. endpoint
  local api_client = helpers.admin_client()
  local res, err = assert(api_client:send {
    method = "POST",
    path = url,
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
local patch_upstream
local get_upstream
local get_upstream_health
local post_target_address_health
local get_router_version
local add_target
local add_api
local patch_api
local gen_port
local gen_multi_host
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
      path = path,
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
    local upstream_name = gen_sym("upstream")
    if TEST_LOG then
      print("ADDING UPSTREAM ", upstream_id)
    end
    local req = utils.deep_copy(data) or {}
    req.name = req.name or upstream_name
    req.slots = req.slots or SLOTS
    req.id = upstream_id
    bp.upstreams:insert(req)
    return upstream_name, upstream_id
  end

  patch_upstream = function(upstream_id, data)
    assert.same(200, api_send("PATCH", "/upstreams/" .. upstream_id, data))
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
      return os.execute("netstat -n | grep -w " .. port)
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
    bp.targets:insert(req)
    return port
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


local function end_testcase_setup(strategy, bp)
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
    assert.res_status(201, res)
    admin_client:close()
  end
end


local function get_db_utils_for_dc_and_admin_api(strategy, tables)
  local bp = assert(helpers.get_db_utils(strategy, tables))
  if strategy ~= "off" then
    bp = require("spec.fixtures.admin_api")
  end
  return bp
end


local localhosts = {
  ipv4 = "127.0.0.1",
  ipv6 = "[0000:0000:0000:0000:0000:0000:0000:0001]",
  hostname = "localhost",
}


for _, strategy in helpers.each_strategy() do

  local bp

  describe("Ring-balancer resolution #" .. strategy, function()

    lazy_setup(function()
      bp = get_db_utils_for_dc_and_admin_api(strategy, {
        "routes",
        "services",
        "plugins",
        "upstreams",
        "targets",
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:SRV {
        name = "my.srv.test.com",
        target = "a.my.srv.test.com",
        port = 80,  -- port should fail to connect
      }
      fixtures.dns_mock:A {
        name = "a.my.srv.test.com",
        address = "127.0.0.1",
      }

      fixtures.dns_mock:A {
        name = "multiple-ips.test",
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = "multiple-ips.test",
        address = "127.0.0.2",
      }

      fixtures.dns_mock:SRV {
        name = "srv-changes-port.test",
        target = "a-changes-port.test",
        port = 90,  -- port should fail to connect
      }

      fixtures.dns_mock:A {
        name = "a-changes-port.test",
        address = "127.0.0.3",
      }
      fixtures.dns_mock:A {
        name = "another.multiple-ips.test",
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = "another.multiple-ips.test",
        address = "127.0.0.2",
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = 0.1,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("2-level dns sets the proper health-check", function()

      -- Issue is that 2 level dns hits a mismatch between a name
      -- in the second level, and the IP address that failed.
      -- Typically an SRV pointing to an A record will result in a
      -- internal balancer structure Address that hold a name rather
      -- than an IP. So when Kong reports IP xyz failed to connect,
      -- and the healthchecker marks it as down. That IP will not be
      -- found in the balancer (since its only known by name), and hence
      -- and error is returned that the target could not be disabled.

      -- configure healthchecks
      begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = add_upstream(bp, {
        healthchecks = healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      add_target(bp, upstream_id, "my.srv.test.com", 80)
      local api_host = add_api(bp, upstream_name)
      end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = client_requests(SLOTS, api_host)
      assert.same(0, oks)
      assert.same(10, fails)
      assert.same(503, last_status)

      local health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.equals("UNHEALTHY", health.data[1].health)
    end)

    it("a target that resolves to 2 IPs reports health separately", function()

      -- configure healthchecks
      begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = add_upstream(bp, {
        healthchecks = healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      add_target(bp, upstream_id, "multiple-ips.test", 80)
      local api_host = add_api(bp, upstream_name)
      end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = client_requests(SLOTS, api_host)
      assert.same(0, oks)
      assert.same(10, fails)
      assert.same(503, last_status)

      local health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

      local status = post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "healthy")
      assert.same(204, status)

      health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[2].health)

      local status = post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "unhealthy")
      assert.same(204, status)

      health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

    end)

    it("a target that resolves to 2 IPs reports health separately (upstream with hostname set)", function()

      -- configure healthchecks
      begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = add_upstream(bp, {
        host_header = "another.multiple-ips.test",
        healthchecks = healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      add_target(bp, upstream_id, "multiple-ips.test", 80)
      local api_host = add_api(bp, upstream_name)
      end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = client_requests(SLOTS, api_host)
      assert.same(0, oks)
      assert.same(10, fails)
      assert.same(503, last_status)

      local health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

      local status = post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "healthy")
      assert.same(204, status)

      health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[2].health)

      local status = post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "unhealthy")
      assert.same(204, status)

      health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

    end)

    it("a target that resolves to an SRV record that changes port", function()

      -- configure healthchecks
      begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = add_upstream(bp, {
        healthchecks = healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      add_target(bp, upstream_id, "srv-changes-port.test", 80)
      local api_host = add_api(bp, upstream_name)
      end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = client_requests(SLOTS, api_host)
      assert.same(0, oks)
      assert.same(10, fails)
      assert.same(503, last_status)

      local health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("a-changes-port.test", health.data[1].data.addresses[1].ip)
      assert.same(90, health.data[1].data.addresses[1].port)

      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)

      local status = post_target_address_health(upstream_id, "srv-changes-port.test:80", "a-changes-port.test:90", "healthy")
      assert.same(204, status)

      health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("a-changes-port.test", health.data[1].data.addresses[1].ip)
      assert.same(90, health.data[1].data.addresses[1].port)

      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[1].health)
    end)

    it("a target that has healthchecks disabled", function()
      -- configure healthchecks
      begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = add_upstream(bp, {
        healthchecks = healthchecks_config {
          passive = {
            unhealthy = {
              http_failures = 0,
              tcp_failures = 0,
              timeouts = 0,
            },
          },
          active = {
            healthy = {
              interval = 0,
            },
            unhealthy = {
              interval = 0,
            },
          },
        }
      })
      add_target(bp, upstream_id, "multiple-ips.test", 80)
      add_api(bp, upstream_name)
      end_testcase_setup(strategy, bp)
      local health = get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.equals("HEALTHCHECKS_OFF", health.data[1].health)
      assert.equals("HEALTHCHECKS_OFF", health.data[1].data.addresses[1].health)
    end)

  end)

  describe("Ring-balancer #" .. strategy, function()

    lazy_setup(function()
      bp = get_db_utils_for_dc_and_admin_api(strategy, {
        "services",
        "routes",
        "upstreams",
        "targets",
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
        stream_listen = "0.0.0.0:9100",
        db_update_frequency = 0.1,
        plugins = "bundled,fail-once-auth",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("#healthchecks (#cluster #db)", function()

      -- second node ports are Kong test ports + 10
      local proxy_port_1 = 9000
      local admin_port_1 = 9001
      local proxy_port_2 = 9010
      local admin_port_2 = 9011

      lazy_setup(function()
        -- start a second Kong instance
        helpers.start_kong({
          database   = strategy,
          admin_listen = "127.0.0.1:" .. admin_port_2,
          proxy_listen = "127.0.0.1:" .. proxy_port_2,
          stream_listen = "off",
          prefix = "servroot2",
          log_level = "debug",
          db_update_frequency = 0.1,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
      end)

      for mode, localhost in pairs(localhosts) do

        describe("#" .. mode, function()

          it("does not perform health checks when disabled (#3304)", function()

            begin_testcase_setup(strategy, bp)
            local old_rv = get_router_version(admin_port_2)
            local upstream_name, upstream_id = add_upstream(bp)
            local port = add_target(bp, upstream_id, localhost)
            local api_host = add_api(bp, upstream_name)
            wait_for_router_update(bp, old_rv, localhost, proxy_port_2, admin_port_2)
            end_testcase_setup(strategy, bp)

            -- server responds, then fails, then responds again
            local server = http_server(localhost, port, { 20, 20, 20 })

            local seq = {
              { port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_2, oks = 0, fails = 10, last_status = 500 },
              { port = proxy_port_1, oks = 0, fails = 10, last_status = 500 },
              { port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
            }
            for i, test in ipairs(seq) do
              local oks, fails, last_status = client_requests(10, api_host, "127.0.0.1", test.port)
              assert.same(test.oks, oks, "iteration " .. tostring(i))
              assert.same(test.fails, fails, "iteration " .. tostring(i))
              assert.same(test.last_status, last_status, "iteration " .. tostring(i))
            end

            -- collect server results
            local _, server_oks, server_fails = server:done()
            assert.same(40, server_oks)
            assert.same(20, server_fails)

          end)

          it("propagates posted health info #flaky", function()

            begin_testcase_setup(strategy, bp)
            local old_rv = get_router_version(admin_port_2)
            local _, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {}
            })
            local port = add_target(bp, upstream_id, localhost)
            wait_for_router_update(old_rv, localhost, proxy_port_2, admin_port_2)
            end_testcase_setup(strategy, bp)

            local health1 = get_upstream_health(upstream_id, admin_port_1)
            local health2 = get_upstream_health(upstream_id, admin_port_2)

            assert.same("HEALTHY", health1.data[1].health)
            assert.same("HEALTHY", health2.data[1].health)

            post_target_endpoint(upstream_id, localhost, port, "unhealthy")

            poll_wait_health(upstream_id, localhost, port, "UNHEALTHY", admin_port_1)
            poll_wait_health(upstream_id, localhost, port, "UNHEALTHY", admin_port_2)

          end)

        end)
      end
    end)

    for mode, localhost in pairs(localhosts) do

      describe("#" .. mode, function()

        describe("Upstream entities", function()

          -- Regression test for a missing invalidation in 0.12rc1
          it("created via the API are functional", function()
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp)
            local target_port = add_target(bp, upstream_id, localhost)
            local api_host = add_api(bp, upstream_name)
            end_testcase_setup(strategy, bp)

            local server = http_server(localhost, target_port, { 1 })

            local oks, fails, last_status = client_requests(1, api_host)
            assert.same(200, last_status)
            assert.same(1, oks)
            assert.same(0, fails)

            local _, server_oks, server_fails = server:done()
            assert.same(1, server_oks)
            assert.same(0, server_fails)
          end)

          it("created via the API are functional #grpc", function()
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp)
            add_target(bp, upstream_id, localhost, 15002)
            local api_host = add_api(bp, upstream_name, {
              service_protocol = "grpc",
              route_protocol = "grpc",
            })
            end_testcase_setup(strategy, bp)

            local grpc_client = helpers.proxy_client_grpc()
            local ok, resp = grpc_client({
              service = "hello.HelloService.SayHello",
              opts = {
                ["-authority"] = api_host,
              }
            })
            assert.Truthy(ok)
            assert.Truthy(resp)
          end)

          it("properly set the host header", function()
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, { host_header = "localhost" })
            local target_port = add_target(bp, upstream_id, localhost)
            local api_host = add_api(bp, upstream_name)
            end_testcase_setup(strategy, bp)

            local server = http_server("localhost", target_port, { 5 }, "false", "http", "true")

            local oks, fails, last_status = client_requests(5, api_host)
            assert.same(200, last_status)
            assert.same(5, oks)
            assert.same(0, fails)

            local _, server_oks, server_fails = server:done()
            assert.same(5, server_oks)
            assert.same(0, server_fails)
          end)

          it("fail with wrong host header", function()
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, { host_header = "localhost" })
            local target_port = add_target(bp, upstream_id, "localhost")
            local api_host = add_api(bp, upstream_name)
            end_testcase_setup(strategy, bp)
            local server = http_server("127.0.0.1", target_port, { 5 }, "false", "http", "true")
            local oks, fails, last_status = client_requests(5, api_host)
            assert.same(400, last_status)
            assert.same(0, oks)
            assert.same(5, fails)

            -- oks and fails must be 0 as localhost should not receive any request
            local _, server_oks, server_fails = server:done()
            assert.same(0, server_oks)
            assert.same(0, server_fails)
          end)

          -- #db == disabled for database=off, because it tests
          -- for a PATCH operation
          it("#db can have their config partially updated", function()
            begin_testcase_setup(strategy, bp)
            local _, upstream_id = add_upstream(bp)
            end_testcase_setup(strategy, bp)

            begin_testcase_setup_update(strategy, bp)
            patch_upstream(upstream_id, {
              healthchecks = {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = 0,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = 0,
                    http_failures = 1,
                  },
                }
              }
            })
            end_testcase_setup(strategy, bp)

            local updated = {
              active = {
                type = "http",
                concurrency = 10,
                healthy = {
                  http_statuses = { 200, 302 },
                  interval = 0,
                  successes = 1
                },
                http_path = "/status",
                https_sni = cjson.null,
                https_verify_certificate = true,
                timeout = 1,
                unhealthy = {
                  http_failures = 1,
                  http_statuses = { 429, 404, 500, 501, 502, 503, 504, 505 },
                  interval = 0,
                  tcp_failures = 0,
                  timeouts = 0
                }
              },
              passive = {
                type = "http",
                healthy = {
                  http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                                    300, 301, 302, 303, 304, 305, 306, 307, 308 },
                  successes = 0
                },
                unhealthy = {
                  http_failures = 0,
                  http_statuses = { 429, 500, 503 },
                  tcp_failures = 0,
                  timeouts = 0
                }
              }
            }

            local upstream_data = get_upstream(upstream_id)
            assert.same(updated, upstream_data.healthchecks)
          end)

          -- #db == disabled for database=off, because it tests
          -- for a PATCH operation.
          -- TODO produce an equivalent test when upstreams are preserved
          -- (not rebuilt) across declarative config updates.
          it("#db can be renamed without producing stale cache", function()
            -- create two upstreams, each with a target pointing to a server
            begin_testcase_setup(strategy, bp)
            local upstreams = {}
            for i = 1, 2 do
              upstreams[i] = {}
              upstreams[i].name = add_upstream(bp, {
                healthchecks = healthchecks_config {}
              })
              upstreams[i].port = add_target(bp, upstreams[i].name, localhost)
              upstreams[i].api_host = add_api(bp, upstreams[i].name)
            end
            end_testcase_setup(strategy, bp)

            -- start two servers
            local server1 = http_server(localhost, upstreams[1].port, { 1 })
            local server2 = http_server(localhost, upstreams[2].port, { 1 })

            -- rename upstream 2
            local new_name = upstreams[2].name .. "_new"
            patch_upstream(upstreams[2].name, {
              name = new_name,
            })

            -- rename upstream 1 to upstream 2's original name
            patch_upstream(upstreams[1].name, {
              name = upstreams[2].name,
            })

            -- hit a request through upstream 1 using the new name
            local oks, fails, last_status = client_requests(1, upstreams[2].api_host)
            assert.same(200, last_status)
            assert.same(1, oks)
            assert.same(0, fails)

            -- rename upstream 2
            patch_upstream(new_name, {
              name = upstreams[1].name,
            })

            -- a single request to upstream 2 just to make server 2 shutdown
            client_requests(1, upstreams[1].api_host)

            -- collect results
            local _, server1_oks, server1_fails = server1:done()
            local _, server2_oks, server2_fails = server2:done()
            assert.same({1, 0}, { server1_oks, server1_fails })
            assert.same({1, 0}, { server2_oks, server2_fails })
          end)

          -- #db == disabled for database=off, because it tests
          -- for a PATCH operation.
          -- TODO produce an equivalent test when upstreams are preserved
          -- (not rebuilt) across declarative config updates.
          it("#db do not leave a stale healthchecker when renamed", function()

            begin_testcase_setup(strategy, bp)

            -- create an upstream
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    http_failures = 1,
                  },
                }
              }
            })
            local port = add_target(bp, upstream_id, localhost)
            local _, service_id = add_api(bp, upstream_name)

            end_testcase_setup(strategy, bp)

            -- rename upstream
            local new_name = upstream_id .. "_new"
            patch_upstream(upstream_id, {
              name = new_name
            })

            -- reconfigure healthchecks
            patch_upstream(new_name, {
              healthchecks = {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = 0,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = 0,
                    http_failures = 1,
                  },
                }
              }
            })

            -- start server
            local server1 = http_server(localhost, port, { 1 })

            -- give time for healthchecker to (not!) run
            ngx.sleep(HEALTHCHECK_INTERVAL * 3)

            begin_testcase_setup_update(strategy, bp)
            patch_api(bp, service_id, "http://" .. new_name)
            end_testcase_setup(strategy, bp)

            -- collect results
            local _, server1_oks, server1_fails, hcs = server1:done()
            assert.same({0, 0}, { server1_oks, server1_fails })
            assert.truthy(hcs < 2)
          end)

        end)

        describe("#healthchecks", function()

          local stream_it = (mode == "ipv6" or strategy == "off") and pending or it

          it("do not count Kong-generated errors as failures", function()

            begin_testcase_setup(strategy, bp)

            -- configure healthchecks with a 1-error threshold
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                passive = {
                  healthy = {
                    successes = 1,
                  },
                  unhealthy = {
                    http_statuses = { 401, 500 },
                    http_failures = 1,
                    tcp_failures = 1,
                    timeouts = 1,
                  },
                }
              }
            })
            local port1 = add_target(bp, upstream_id, localhost)
            local port2 = add_target(bp, upstream_id, localhost)
            local api_host, service_id = add_api(bp, upstream_name)

            -- add a plugin
            local plugin_id = utils.uuid()
            bp.plugins:insert({
              id = plugin_id,
              service = { id = service_id },
              name = "fail-once-auth",
            })

            end_testcase_setup(strategy, bp)

            -- run request: fails with 401, but doesn't hit the 1-error threshold
            local oks, fails, last_status = client_requests(1, api_host)
            assert.same(0, oks)
            assert.same(1, fails)
            assert.same(401, last_status)

            -- start servers, they are unaffected by the failure above
            local server1 = http_server(localhost, port1, { SLOTS })
            local server2 = http_server(localhost, port2, { SLOTS })

            oks, fails = client_requests(SLOTS * 2, api_host)
            assert.same(SLOTS * 2, oks)
            assert.same(0, fails)

            -- collect server results
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- both servers were fully operational
            assert.same(SLOTS, ok1)
            assert.same(SLOTS, ok2)
            assert.same(0, fail1)
            assert.same(0, fail2)

          end)

          it("perform passive health checks", function()

            for nfails = 1, 3 do

              begin_testcase_setup(strategy, bp)
              -- configure healthchecks
              local upstream_name, upstream_id = add_upstream(bp, {
                healthchecks = healthchecks_config {
                  passive = {
                    unhealthy = {
                      http_failures = nfails,
                    }
                  }
                }
              })
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              local requests = SLOTS * 2 -- go round the balancer twice

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server2_oks = math.floor(requests / 4)
              local server1 = http_server(localhost, port1, {
                requests - server2_oks - nfails
              })
              local server2 = http_server(localhost, port2, {
                server2_oks,
                nfails
              })

              -- Go hit them with our test requests
              local client_oks, client_fails = client_requests(requests, api_host)

              -- collect server results; hitcount
              local _, ok1, fail1 = server1:done()
              local _, ok2, fail2 = server2:done()

              -- verify
              assert.are.equal(requests - server2_oks - nfails, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fail1)
              assert.are.equal(nfails, fail2)

              assert.are.equal(requests - nfails, client_oks)
              assert.are.equal(nfails, client_fails)
            end
          end)

          stream_it("#stream and http modules do not duplicate active health checks", function()

            local port1 = gen_port()

            local server1 = http_server(localhost, port1, { 1 })

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local _, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    http_failures = 1,
                  },
                }
              }
            })
            add_target(bp, upstream_id, localhost, port1)
            end_testcase_setup(strategy, bp)

            ngx.sleep(HEALTHCHECK_INTERVAL * 5)

            -- collect server results; hitcount
            local _, _, _, hcs1 = server1:done()

            assert(hcs1 < 8)
          end)

          it("perform active health checks -- up then down", function()

            for nfails = 1, 3 do

              local requests = SLOTS * 2 -- go round the balancer twice
              local port1 = gen_port()
              local port2 = gen_port()

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server2_oks = math.floor(requests / 4)
              local server1 = http_server(localhost, port1, { requests - server2_oks })
              local server2 = http_server(localhost, port2, { server2_oks })

              -- configure healthchecks
              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp, {
                healthchecks = healthchecks_config {
                  active = {
                    http_path = "/status",
                    healthy = {
                      interval = HEALTHCHECK_INTERVAL,
                      successes = 1,
                    },
                    unhealthy = {
                      interval = HEALTHCHECK_INTERVAL,
                      http_failures = nfails,
                    },
                  }
                }
              })
              add_target(bp, upstream_id, localhost, port1)
              add_target(bp, upstream_id, localhost, port2)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- Phase 1: server1 and server2 take requests
              local client_oks, client_fails = client_requests(server2_oks * 2, api_host)

              -- Phase 2: server2 goes unhealthy
              direct_request(localhost, port2, "/unhealthy")

              -- Give time for healthchecker to detect
              poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")

              -- Phase 3: server1 takes all requests
              do
                local p3oks, p3fails = client_requests(requests - (server2_oks * 2), api_host)
                client_oks = client_oks + p3oks
                client_fails = client_fails + p3fails
              end

              -- collect server results; hitcount
              local _, ok1, fail1 = server1:done()
              local _, ok2, fail2 = server2:done()

              -- verify
              assert.are.equal(requests - server2_oks, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fail1)
              assert.are.equal(0, fail2)

              assert.are.equal(requests, client_oks)
              assert.are.equal(0, client_fails)
            end
          end)

          it("perform active health checks with upstream hostname", function()

            for nfails = 1, 3 do

              local requests = SLOTS * 2 -- go round the balancer twice
              local port1 = gen_port()
              local port2 = gen_port()

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server2_oks = math.floor(requests / 4)
              local server1 = http_server("localhost", port1,
                { requests - server2_oks }, "false", "http", "true")
              local server2 = http_server("localhost", port2, { server2_oks },
                "false", "http", "true")

              -- configure healthchecks
              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp, {
                host_header = "localhost",
                healthchecks = healthchecks_config {
                  active = {
                    http_path = "/status",
                    healthy = {
                      interval = HEALTHCHECK_INTERVAL,
                      successes = 1,
                    },
                    unhealthy = {
                      interval = HEALTHCHECK_INTERVAL,
                      http_failures = nfails,
                    },
                  }
                }
              })
              add_target(bp, upstream_id, localhost, port1)
              add_target(bp, upstream_id, localhost, port2)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- Phase 1: server1 and server2 take requests
              local client_oks, client_fails = client_requests(server2_oks * 2, api_host)

              -- Phase 2: server2 goes unhealthy
              direct_request("localhost", port2, "/unhealthy")

              -- Give time for healthchecker to detect
              poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")

              -- Phase 3: server1 takes all requests
              do
                local p3oks, p3fails = client_requests(requests - (server2_oks * 2), api_host)
                client_oks = client_oks + p3oks
                client_fails = client_fails + p3fails
              end

              -- collect server results; hitcount
              local _, ok1, fail1 = server1:done()
              local _, ok2, fail2 = server2:done()

              -- verify
              assert.are.equal(requests - server2_oks, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fail1)
              assert.are.equal(0, fail2)

              assert.are.equal(requests, client_oks)
              assert.are.equal(0, client_fails)
            end
          end)

          for _, protocol in ipairs({"http", "https"}) do
            it("perform active health checks -- automatic recovery #" .. protocol, function()
              for nchecks = 1, 3 do

                local port1 = gen_port()
                local port2 = gen_port()

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server1_oks = SLOTS * 2
                local server2_oks = SLOTS
                local server1 = http_server(localhost, port1, { server1_oks }, nil, protocol)
                local server2 = http_server(localhost, port2, { server2_oks }, nil, protocol)

                -- configure healthchecks
                begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = add_upstream(bp, {
                  healthchecks = healthchecks_config {
                    active = {
                      type = protocol,
                      http_path = "/status",
                      https_verify_certificate = (protocol == "https" and localhost == "localhost"),
                      healthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        successes = nchecks,
                      },
                      unhealthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        http_failures = nchecks,
                      },
                    }
                  }
                })
                add_target(bp, upstream_id, localhost, port1)
                add_target(bp, upstream_id, localhost, port2)
                local api_host = add_api(bp, upstream_name, {
                  service_protocol = protocol
                })

                end_testcase_setup(strategy, bp)

                -- ensure it's healthy at the beginning of the test
                direct_request(localhost, port1, "/healthy", protocol)
                direct_request(localhost, port2, "/healthy", protocol)
                poll_wait_health(upstream_id, localhost, port1, "HEALTHY")
                poll_wait_health(upstream_id, localhost, port2, "HEALTHY")

                -- 1) server1 and server2 take requests
                local oks, fails = client_requests(SLOTS, api_host)

                -- server2 goes unhealthy
                direct_request(localhost, port2, "/unhealthy", protocol)
                -- Wait until healthchecker detects
                poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")

                -- 2) server1 takes all requests
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- server2 goes healthy again
                direct_request(localhost, port2, "/healthy", protocol)
                -- Give time for healthchecker to detect
                poll_wait_health(upstream_id, localhost, port2, "HEALTHY")

                -- 3) server1 and server2 take requests again
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- collect server results; hitcount
                local _, ok1, fail1 = server1:done()
                local _, ok2, fail2 = server2:done()

                -- verify
                assert.are.equal(SLOTS * 2, ok1)
                assert.are.equal(SLOTS, ok2)
                assert.are.equal(0, fail1)
                assert.are.equal(0, fail2)

                assert.are.equal(SLOTS * 3, oks)
                assert.are.equal(0, fails)
              end
            end)

            it("perform active health checks on a target that resolves to multiple addresses -- automatic recovery #" .. protocol, function()
              local hosts = {}

              local dns_mock_filename = helpers.test_conf.prefix .. "/dns_mock_records.lua"
              finally(function()
                os.remove(dns_mock_filename)
              end)

              local fixtures = {
                dns_mock = helpers.dns_mock.new()
              }

              for i = 1, 3 do
                hosts[i] = {
                  hostname = gen_multi_host(),
                  port1 = gen_port(),
                  port2 = gen_port(),
                }
                fixtures.dns_mock:SRV {
                  name = hosts[i].hostname,
                  target = localhost,
                  port = hosts[i].port1,
                }
                fixtures.dns_mock:SRV {
                  name = hosts[i].hostname,
                  target = localhost,
                  port = hosts[i].port2,
                }
              end

              -- restart Kong
              begin_testcase_setup_update(strategy, bp)
              helpers.restart_kong({
                database = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
                db_update_frequency = 0.1,
                stream_listen = "0.0.0.0:9100",
                plugins = "bundled,fail-once-auth",
              }, nil, fixtures)
              end_testcase_setup(strategy, bp)
              ngx.sleep(0.5)

              for nchecks = 1, 3 do

                local port1 = hosts[nchecks].port1
                local port2 = hosts[nchecks].port2
                local hostname = hosts[nchecks].hostname

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server1_oks = SLOTS * 2
                local server2_oks = SLOTS
                local server1 = http_server(localhost, port1, { server1_oks }, nil, protocol)
                local server2 = http_server(localhost, port2, { server2_oks }, nil, protocol)

                -- configure healthchecks
                begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = add_upstream(bp, {
                  healthchecks = healthchecks_config {
                    active = {
                      type = protocol,
                      http_path = "/status",
                      https_verify_certificate = (protocol == "https" and hostname == "localhost"),
                      healthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        successes = nchecks,
                      },
                      unhealthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        http_failures = nchecks,
                      },
                    }
                  }
                })
                add_target(bp, upstream_id, hostname, port1) -- port gets overridden at DNS resolution
                local api_host = add_api(bp, upstream_name, {
                  service_protocol = protocol
                })

                end_testcase_setup(strategy, bp)

                -- 1) server1 and server2 take requests
                local oks, fails = client_requests(SLOTS, api_host)

                -- server2 goes unhealthy
                direct_request(localhost, port2, "/unhealthy", protocol, hostname)
                -- Wait until healthchecker detects
                poll_wait_address_health(upstream_id, hostname, port1, localhost, port2, "UNHEALTHY")

                -- 2) server1 takes all requests
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- server2 goes healthy again
                direct_request(localhost, port2, "/healthy", protocol, hostname)
                -- Give time for healthchecker to detect
                poll_wait_address_health(upstream_id, hostname, port1, localhost, port2, "HEALTHY")

                -- 3) server1 and server2 take requests again
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- collect server results; hitcount
                local _, ok1, fail1 = server1:done(hostname)
                local _, ok2, fail2 = server2:done(hostname)

                -- verify
                assert.are.equal(SLOTS * 2, ok1)
                assert.are.equal(SLOTS, ok2)
                assert.are.equal(0, fail1)
                assert.are.equal(0, fail2)

                assert.are.equal(SLOTS * 3, oks)
                assert.are.equal(0, fails)
              end
            end)

            it("perform active health checks on targets that resolve to the same IP -- automatic recovery #" .. protocol, function()
              local dns_mock_filename = helpers.test_conf.prefix .. "/dns_mock_records.lua"
              finally(function()
                os.remove(dns_mock_filename)
              end)

              local fixtures = {
                dns_mock = helpers.dns_mock.new()
              }

              fixtures.dns_mock:A {
                name = "target1.test",
                address = "127.0.0.1",
              }
              fixtures.dns_mock:A {
                name = "target2.test",
                address = "127.0.0.1",
              }

              -- restart Kong
              begin_testcase_setup_update(strategy, bp)
              helpers.restart_kong({
                database = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
                db_update_frequency = 0.1,
                stream_listen = "0.0.0.0:9100",
                plugins = "bundled,fail-once-auth",
              }, nil, fixtures)
              end_testcase_setup(strategy, bp)
              ngx.sleep(1)

              for nchecks = 1, 3 do

                local port1 = gen_port()
                local hostname = localhost

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local target1_oks = SLOTS * 2
                local target2_oks = SLOTS
                local counts = {
                  ["target1.test"] = { target1_oks },
                  ["target2.test"] = { target2_oks },
                }
                local server1 = http_server(localhost, port1, counts, nil, protocol)

                -- configure healthchecks
                begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = add_upstream(bp, {
                  healthchecks = healthchecks_config {
                    active = {
                      type = protocol,
                      http_path = "/status",
                      https_verify_certificate = false,
                      healthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        successes = nchecks,
                      },
                      unhealthy = {
                        interval = HEALTHCHECK_INTERVAL,
                        http_failures = nchecks,
                      },
                    }
                  }
                })
                add_target(bp, upstream_id, "target1.test", port1)
                add_target(bp, upstream_id, "target2.test", port1)
                local api_host = add_api(bp, upstream_name, {
                  service_protocol = protocol
                })

                end_testcase_setup(strategy, bp)

                -- 1) target1 and target2 take requests
                local oks, fails = client_requests(SLOTS, api_host)

                -- target2 goes unhealthy
                direct_request(localhost, port1, "/unhealthy", protocol, "target2.test")
                -- Wait until healthchecker detects
                poll_wait_health(upstream_id, "target2.test", port1, "UNHEALTHY")

                -- 2) target1 takes all requests
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- target2 goes healthy again
                direct_request(localhost, port1, "/healthy", protocol, "target2.test")
                -- Give time for healthchecker to detect
                poll_wait_health(upstream_id, "target2.test", port1, "HEALTHY")

                -- 3) server1 and server2 take requests again
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- collect server results; hitcount
                local results1 = direct_request(localhost, port1, "/results", protocol, "target1.test")
                local results2 = direct_request(localhost, port1, "/results", protocol, "target2.test")

                local target1_results
                local target2_results
                if results1 then
                  target1_results = assert(cjson.decode(results1))
                end
                if results2 then
                  target2_results = assert(cjson.decode(results2))
                end

                server1:done(hostname)

                -- verify
                assert.are.equal(SLOTS * 2, target1_results.ok_responses)
                assert.are.equal(SLOTS, target2_results.ok_responses)
                assert.are.equal(0, target1_results.fail_responses)
                assert.are.equal(0, target2_results.fail_responses)

                assert.are.equal(SLOTS * 3, oks)
                assert.are.equal(0, fails)
              end
            end)
          end

          it("#flaky #db perform active health checks -- automatic recovery #stream", function()

            local port1 = gen_port()
            local port2 = gen_port()

            -- setup target servers:
            -- server2 will only respond for part of the test,
            -- then server1 will take over.
            local server1 = helpers.tcp_server(port1, {
              requests = 1000,
              prefix = "1 ",
            })
            local server2 = helpers.tcp_server(port2, {
              requests = 1000,
              prefix = "2 ",
            })
            ngx.sleep(0.1)

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                active = {
                  type = "tcp",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    tcp_failures = 1,
                  },
                }
              }
            })

            add_target(bp, upstream_id, localhost, port1)
            add_target(bp, upstream_id, localhost, port2)
            local _, service_id, route_id = add_api(bp, upstream_name, {
              read_timeout = 500,
              write_timeout = 500,
              route_protocol = "tcp",
            })
            end_testcase_setup(strategy, bp)

            finally(function()
              helpers.kill_tcp_server(port1)
              helpers.kill_tcp_server(port2)
              server1:join()
              server2:join()

              bp.routes:remove({ id = route_id })
              bp.services:remove({ id = service_id })
            end)

            ngx.sleep(0.5)

            -- 1) server1 and server2 take requests
            local ok1, ok2 = tcp_client_requests(SLOTS * 2, localhost, 9100)
            assert.same(SLOTS, ok1)
            assert.same(SLOTS, ok2)

            -- server2 goes unhealthy
            helpers.kill_tcp_server(port2)
            server2:join()

            -- Wait until healthchecker detects
            -- We cannot use poll_wait_health because health endpoints
            -- are not currently available for stream routes.
            ngx.sleep(strategy == "cassandra" and 2 or 1)

            -- 2) server1 takes all requests
            ok1, ok2 = tcp_client_requests(SLOTS * 2, localhost, 9100)
            assert.same(SLOTS * 2, ok1)
            assert.same(0, ok2)

            -- server2 goes healthy again
            server2 = helpers.tcp_server(port2, {
              requests = 1000,
              prefix = "2 ",
            })

            -- Give time for healthchecker to detect
            -- Again, we cannot use poll_wait_health because health endpoints
            -- are not currently available for stream routes.
            ngx.sleep(strategy == "cassandra" and 2 or 1)

            -- 3) server1 and server2 take requests again
            ok1, ok2 = tcp_client_requests(SLOTS * 2, localhost, 9100)
            assert.same(SLOTS, ok1)
            assert.same(SLOTS, ok2)
          end)

          -- FIXME This is marked as #flaky because of Travis CI instability.
          -- This runs fine on other environments. This should be re-checked
          -- at a later time.
          it("#flaky perform active health checks -- can detect before any proxy traffic", function()

            local nfails = 2
            local requests = SLOTS * 2 -- go round the balancer twice
            local port1 = gen_port()
            local port2 = gen_port()
            -- setup target servers:
            -- server1 will respond all requests
            local server1 = http_server(localhost, port1, { requests })
            local server2 = http_server(localhost, port2, { requests })
            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    http_failures = nfails,
                    tcp_failures = nfails,
                  },
                }
              }
            })
            add_target(bp, upstream_id, localhost, port1)
            add_target(bp, upstream_id, localhost, port2)
            local api_host = add_api(bp, upstream_name)
            end_testcase_setup(strategy, bp)

            -- server2 goes unhealthy before the first request
            direct_request(localhost, port2, "/unhealthy")

            -- restart Kong
            begin_testcase_setup_update(strategy, bp)
            helpers.restart_kong({
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
              lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
              db_update_frequency = 0.1,
              stream_listen = "0.0.0.0:9100",
              plugins = "bundled,fail-once-auth",
            })
            end_testcase_setup(strategy, bp)
            ngx.sleep(1)

            -- Give time for healthchecker to detect
            poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")

            -- server1 takes all requests

            local client_oks, client_fails = client_requests(requests, api_host)

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(requests, ok1)
            assert.are.equal(0, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(0, fail2)

            assert.are.equal(requests, client_oks)
            assert.are.equal(0, client_fails)

          end)

          it("perform passive health checks -- manual recovery", function()

            for nfails = 1, 3 do
              -- configure healthchecks
              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp, {
                healthchecks = healthchecks_config {
                  passive = {
                    unhealthy = {
                      http_failures = nfails,
                    }
                  }
                }
              })
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server1_oks = SLOTS * 2 - nfails
              local server2_oks = SLOTS
              local server1 = http_server(localhost, port1, {
                server1_oks
              })
              local server2 = http_server(localhost, port2, {
                server2_oks / 2,
                nfails,
                server2_oks / 2
              })

              -- 1) server1 and server2 take requests
              local oks, fails = client_requests(SLOTS, api_host)

              -- 2) server1 takes all requests once server2 produces
              -- `nfails` failures (even though server2 will be ready
              -- to respond 200 again after `nfails`)
              do
                local o, f = client_requests(SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- manually bring it back using the endpoint
              post_target_endpoint(upstream_id, localhost, port2, "healthy")

              -- 3) server1 and server2 take requests again
              do
                local o, f = client_requests(SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- collect server results; hitcount
              local _, ok1, fail1 = server1:done()
              local _, ok2, fail2 = server2:done()

              -- verify
              assert.are.equal(server1_oks, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fail1)
              assert.are.equal(nfails, fail2)

              assert.are.equal(SLOTS * 3 - nfails, oks)
              assert.are.equal(nfails, fails)
            end
          end)

          it("perform passive health checks -- manual shutdown", function()

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = 1,
                  }
                }
              }
            })
            local port1 = add_target(bp, upstream_id, localhost)
            local port2 = add_target(bp, upstream_id, localhost)
            local api_host = add_api(bp, upstream_name)
            end_testcase_setup(strategy, bp)

            -- setup target servers:
            -- server2 will only respond for part of the test,
            -- then server1 will take over.
            local server1_oks = SLOTS * 2
            local server2_oks = SLOTS
            local server1 = http_server(localhost, port1, { server1_oks })
            local server2 = http_server(localhost, port2, { server2_oks })

            -- 1) server1 and server2 take requests
            local oks, fails = client_requests(SLOTS, api_host)

            -- manually bring it down using the endpoint
            post_target_endpoint(upstream_id, localhost, port2, "unhealthy")

            -- 2) server1 takes all requests
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- manually bring it back using the endpoint
            post_target_endpoint(upstream_id, localhost, port2, "healthy")

            -- 3) server1 and server2 take requests again
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(SLOTS * 2, ok1)
            assert.are.equal(SLOTS, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(0, fail2)

            assert.are.equal(SLOTS * 3, oks)
            assert.are.equal(0, fails)

          end)

          it("perform passive health checks -- connection #timeouts", function()

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    timeouts = 1,
                  }
                }
              }
            })
            local port1 = add_target(bp, upstream_id, localhost)
            local port2 = add_target(bp, upstream_id, localhost)
            local api_host = add_api(bp, upstream_name, {
              read_timeout = 50,
              write_timeout = 50,
            })
            end_testcase_setup(strategy, bp)

            -- setup target servers:
            -- server2 will only respond for half of the test
            -- then will timeout on the following request.
            -- Then server1 will take over.
            local server1_oks = SLOTS * 1.5
            local server2_oks = SLOTS / 2
            local server1 = http_server(localhost, port1, {
              server1_oks
            })
            local server2 = http_server(localhost, port2, {
              server2_oks,
              TIMEOUT,
            })

            -- 1) server1 and server2 take requests
            local oks, fails = client_requests(SLOTS, api_host)

            -- 2) server1 takes all requests once server2 produces
            -- `nfails` failures (even though server2 will be ready
            -- to respond 200 again after `nfails`)
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(server1_oks, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(1, fail2)

            assert.are.equal(SLOTS * 2, oks)
            assert.are.equal(0, fails)
          end)

          stream_it("#flaky perform passive health checks -- #stream connection failure", function()

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    tcp_failures = 1,
                  }
                }
              }
            })
            local port1 = add_target(bp, upstream_id, localhost)
            local port2 = add_target(bp, upstream_id, localhost)
            local _, service_id, route_id = add_api(bp, upstream_name, {
              read_timeout = 50,
              write_timeout = 50,
              route_protocol = "tcp",
            })
            end_testcase_setup(strategy, bp)

            finally(function()
              bp.routes:remove({ id = route_id })
              bp.services:remove({ id = service_id })
            end)

            -- setup target servers:
            -- server2 will only respond for half of the test and will shutdown.
            -- Then server1 will take over.
            local server1_oks = SLOTS * 1.5
            local server2_oks = SLOTS / 2
            local server1 = helpers.tcp_server(port1, {
              requests = server1_oks,
              prefix = "1 ",
            })
            local server2 = helpers.tcp_server(port2, {
              requests = server2_oks,
              prefix = "2 ",
            })
            ngx.sleep(strategy == "cassandra" and 2 or 1)

            -- server1 and server2 take requests
            -- server1 takes all requests once server2 fails
            local ok1, ok2, fails = tcp_client_requests(SLOTS * 2, localhost, 9100)

            -- finish up TCP server threads
            server1:join()
            server2:join()

            -- verify
            assert.are.equal(server1_oks, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fails)
          end)

          -- #db == disabled for database=off, because healthcheckers
          -- are currently reset when a new configuration is loaded
          -- TODO enable this test when upstreams are preserved (not rebuild)
          -- across a declarative config updates.
          it("#db perform passive health checks -- send #timeouts", function()

            -- configure healthchecks
            begin_testcase_setup(strategy, bp)
            local upstream_name, upstream_id = add_upstream(bp, {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = 0,
                    timeouts = 1,
                    tcp_failures = 0,
                  }
                }
              }
            })
            local port1 = add_target(bp, upstream_id, localhost)
            local api_host, service_id = add_api(bp, upstream_name, {
              read_timeout = 10,
              retries = 0,
            })
            end_testcase_setup(strategy, bp)

            local server1 = http_server(localhost, port1, {
              TIMEOUT,
            })

            local _, _, last_status = client_requests(1, api_host)
            assert.same(504, last_status)

            local _, oks1, fails1 = server1:done()
            assert.same(1, oks1)
            assert.same(0, fails1)

            begin_testcase_setup_update(strategy, bp)
            patch_api(bp, service_id, nil, 60000)
            local port2 = add_target(bp, upstream_id, localhost)
            end_testcase_setup(strategy, bp)

            local server2 = http_server(localhost, port2, {
              10,
            })

            _, _, last_status = client_requests(10, api_host)
            assert.same(200, last_status)

            local _, oks2, fails2 = server2:done()
            assert.same(10, oks2)
            assert.same(0, fails2)
          end)

        end)

        describe("Balancing", function()

          describe("with round-robin", function()

            it("over multiple targets", function()

              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp)
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              local requests = SLOTS * 2 -- go round the balancer twice

              -- setup target servers
              local server1 = http_server(localhost, port1, { requests / 2 })
              local server2 = http_server(localhost, port2, { requests / 2 })

              -- Go hit them with our test requests
              local oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              local _, count1 = server1:done()
              local _, count2 = server2:done()

              -- verify
              assert.are.equal(requests / 2, count1)
              assert.are.equal(requests / 2, count2)
            end)

            it("adding a target", function()

              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp)
              local port1 = add_target(bp, upstream_id, localhost, nil, { weight = 10 })
              local port2 = add_target(bp, upstream_id, localhost, nil, { weight = 10 })
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              local requests = SLOTS * 2 -- go round the balancer twice

              -- setup target servers
              local server1 = http_server(localhost, port1, { requests / 2 })
              local server2 = http_server(localhost, port2, { requests / 2 })

              -- Go hit them with our test requests
              local oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              local _, count1 = server1:done()
              local _, count2 = server2:done()

              -- verify
              assert.are.equal(requests / 2, count1)
              assert.are.equal(requests / 2, count2)

              -- add a new target 3
              -- shift proportions from 50/50 to 40/40/20
              begin_testcase_setup_update(strategy, bp)
              local port3 = add_target(bp, upstream_id, localhost, nil, { weight = 5 })
              end_testcase_setup(strategy, bp)

              -- now go and hit the same balancer again
              -----------------------------------------

              -- setup target servers
              local server3
              server1 = http_server(localhost, port1, { requests * 0.4 })
              server2 = http_server(localhost, port2, { requests * 0.4 })
              server3 = http_server(localhost, port3, { requests * 0.2 })

              -- Go hit them with our test requests
              oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              _, count1 = server1:done()
              _, count2 = server2:done()
              local _, count3 = server3:done()

              -- verify
              assert.are.equal(requests * 0.4, count1)
              assert.are.equal(requests * 0.4, count2)
              assert.are.equal(requests * 0.2, count3)
            end)

            it("removing a target", function()
              local requests = SLOTS * 2 -- go round the balancer twice

              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp)
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- setup target servers
              local server1 = http_server(localhost, port1, { requests / 2 })
              local server2 = http_server(localhost, port2, { requests / 2 })

              -- Go hit them with our test requests
              local oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              local _, count1 = server1:done()
              local _, count2 = server2:done()

              -- verify
              assert.are.equal(requests / 2, count1)
              assert.are.equal(requests / 2, count2)

              -- modify weight for target 2, set to 0
              begin_testcase_setup_update(strategy, bp)
              add_target(bp, upstream_id, localhost, port2, {
                weight = 0, -- disable this target
              })
              end_testcase_setup(strategy, bp)

              -- now go and hit the same balancer again
              -----------------------------------------

              -- setup target servers
              server1 = http_server(localhost, port1, { requests })

              -- Go hit them with our test requests
              oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              _, count1 = server1:done()

              -- verify all requests hit server 1
              assert.are.equal(requests, count1)
            end)
            it("modifying target weight", function()
              local requests = SLOTS * 2 -- go round the balancer twice

              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp)
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- setup target servers
              local server1 = http_server(localhost, port1, { requests / 2 })
              local server2 = http_server(localhost, port2, { requests / 2 })

              -- Go hit them with our test requests
              local oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              local _, count1 = server1:done()
              local _, count2 = server2:done()

              -- verify
              assert.are.equal(requests / 2, count1)
              assert.are.equal(requests / 2, count2)

              -- modify weight for target 2
              begin_testcase_setup_update(strategy, bp)
              add_target(bp, upstream_id, localhost, port2, {
                weight = 15,   -- shift proportions from 50/50 to 40/60
              })
              end_testcase_setup(strategy, bp)

              -- now go and hit the same balancer again
              -----------------------------------------

              -- setup target servers
              server1 = http_server(localhost, port1, { requests * 0.4 })
              server2 = http_server(localhost, port2, { requests * 0.6 })

              -- Go hit them with our test requests
              oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              _, count1 = server1:done()
              _, count2 = server2:done()

              -- verify
              assert.are.equal(requests * 0.4, count1)
              assert.are.equal(requests * 0.6, count2)
            end)

            it("failure due to targets all 0 weight", function()
              local requests = SLOTS * 2 -- go round the balancer twice

              begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = add_upstream(bp)
              local port1 = add_target(bp, upstream_id, localhost)
              local port2 = add_target(bp, upstream_id, localhost)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- setup target servers
              local server1 = http_server(localhost, port1, { requests / 2 })
              local server2 = http_server(localhost, port2, { requests / 2 })

              -- Go hit them with our test requests
              local oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              local _, count1 = server1:done()
              local _, count2 = server2:done()

              -- verify
              assert.are.equal(requests / 2, count1)
              assert.are.equal(requests / 2, count2)

              -- modify weight for both targets, set to 0
              begin_testcase_setup_update(strategy, bp)
              add_target(bp, upstream_id, localhost, port1, { weight = 0 })
              add_target(bp, upstream_id, localhost, port2, { weight = 0 })
              end_testcase_setup(strategy, bp)

              -- now go and hit the same balancer again
              -----------------------------------------

              local _, _, status = client_requests(1, api_host)
              assert.same(503, status)
            end)

          end)

          describe("with consistent hashing", function()

            describe("over multiple targets", function()

              it("hashing on header", function()
                local requests = SLOTS * 2 -- go round the balancer twice

                begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = add_upstream(bp, {
                  hash_on = "header",
                  hash_on_header = "hashme",
                })
                local port1 = add_target(bp, upstream_id, localhost)
                local port2 = add_target(bp, upstream_id, localhost)
                local api_host = add_api(bp, upstream_name)
                end_testcase_setup(strategy, bp)

                -- setup target servers
                local server1 = http_server(localhost, port1, { requests })
                local server2 = http_server(localhost, port2, { requests })

                -- Go hit them with our test requests
                local oks = client_requests(requests, {
                  ["Host"] = api_host,
                  ["hashme"] = "just a value",
                })
                assert.are.equal(requests, oks)

                -- collect server results; hitcount
                -- one should get all the hits, the other 0
                local _, count1 = server1:done()
                local _, count2 = server2:done()

                -- verify
                assert(count1 == 0 or count1 == requests, "counts should either get 0 or ALL hits")
                assert(count2 == 0 or count2 == requests, "counts should either get 0 or ALL hits")
                assert(count1 + count2 == requests)
              end)

              describe("hashing on cookie", function()
                it("does not reply with Set-Cookie if cookie is already set", function()
                  begin_testcase_setup(strategy, bp)
                  local upstream_name, upstream_id = add_upstream(bp, {
                    hash_on = "cookie",
                    hash_on_cookie = "hashme",
                  })
                  local port = add_target(bp, upstream_id, localhost)
                  local api_host = add_api(bp, upstream_name)
                  end_testcase_setup(strategy, bp)

                  -- setup target server
                  local server = http_server(localhost, port, { 1 })

                  -- send request
                  local client = helpers.proxy_client()
                  local res = client:send {
                    method = "GET",
                    path = "/",
                    headers = {
                      ["Host"] = api_host,
                      ["Cookie"] = "hashme=some-cookie-value",
                    }
                  }
                  local set_cookie = res.headers["Set-Cookie"]

                  client:close()
                  server:done()

                  -- verify
                  assert.is_nil(set_cookie)
                end)

                it("replies with Set-Cookie if cookie is not set", function()
                  local requests = SLOTS * 2 -- go round the balancer twice

                  begin_testcase_setup(strategy, bp)
                  local upstream_name, upstream_id = add_upstream(bp, {
                    hash_on = "cookie",
                    hash_on_cookie = "hashme",
                  })
                  local port1 = add_target(bp, upstream_id, localhost)
                  local port2 = add_target(bp, upstream_id, localhost)
                  local api_host = add_api(bp, upstream_name)
                  end_testcase_setup(strategy, bp)

                  -- setup target servers
                  local server1 = http_server(localhost, port1, { requests })
                  local server2 = http_server(localhost, port2, { requests })

                  -- initial request without the `hash_on` cookie
                  local client = helpers.proxy_client()
                  local res = client:send {
                    method = "GET",
                    path = "/",
                    headers = {
                      ["Host"] = api_host,
                      ["Cookie"] = "some-other-cooke=some-other-value",
                    }
                  }
                  local cookie = res.headers["Set-Cookie"]:match("hashme%=(.*)%;")

                  client:close()

                  -- subsequent requests add the cookie that was set by the first response
                  local oks = 1 + client_requests(requests - 1, {
                    ["Host"] = api_host,
                    ["Cookie"] = "hashme=" .. cookie,
                  })
                  assert.are.equal(requests, oks)

                  -- collect server results; hitcount
                  -- one should get all the hits, the other 0
                  local _, count1 = server1:done()
                  local _, count2 = server2:done()

                  -- verify
                  assert(count1 == 0 or count1 == requests,
                         "counts should either get 0 or ALL hits, but got " .. count1 .. " of " .. requests)
                  assert(count2 == 0 or count2 == requests,
                         "counts should either get 0 or ALL hits, but got " .. count2 .. " of " .. requests)
                  assert(count1 + count2 == requests)
                end)

              end)

            end)

          end)

          describe("with no targets", function()

            it("failure due to no targets", function()

              begin_testcase_setup(strategy, bp)
              local upstream_name = add_upstream(bp)
              local api_host = add_api(bp, upstream_name)
              end_testcase_setup(strategy, bp)

              -- Go hit it with a request
              local _, _, status = client_requests(1, api_host)
              assert.same(503, status)

            end)

          end)
        end)
      end)
    end -- for 'localhost'
  end)
end -- for each_strategy

