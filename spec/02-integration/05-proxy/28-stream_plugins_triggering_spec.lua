local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson = require "cjson"
local atc_compat = require "kong.router.compat"


local TEST_CONF = helpers.test_conf
local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"


local function find_in_file(pat, cnt)
  local f = assert(io.open(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log, "r"))
  local line = f:read("*l")
  local count = 0

  while line do
    if line:match(pat) then
      count = count + 1
    end

    line = f:read("*l")
  end

  return cnt == -1 and count >= 1 or count == cnt
end


local function wait()
  -- wait for the second log phase to finish, otherwise it might not appear
  -- in the logs when executing this
  helpers.wait_until(function()
    local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
    local _, count = logs:gsub("%[logger%] log phase", "")

    return count >= 1
  end, 10)
end

-- Phases and counters for unary stream requests

local phases = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] preread phase"] = 1,
  ["%[logger%] log phase"] = 1,
}

local phases_2 = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] preread phase"] = 0,
  ["%[logger%] log phase"] = 1,
}

local phases_tls = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] certificate phase"] = 1,
  ["%[logger%] preread phase"] = 1,
  ["%[logger%] log phase"] = 1,
}

local phases_tls_2 = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] certificate phase"] = 1,
  ["%[logger%] preread phase"] = 0,
  ["%[logger%] log phase"] = 1,
}

local function assert_phases(phrases)
  for phase, count in pairs(phrases) do
    assert(find_in_file(phase, count))
  end
end


local function reload_router(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  helpers.setenv("KONG_ROUTER_FLAVOR", flavor)

  package.loaded["spec.helpers"] = nil
  package.loaded["kong.global"] = nil
  package.loaded["kong.cache"] = nil
  package.loaded["kong.db"] = nil
  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  helpers = require "spec.helpers"

  helpers.unsetenv("KONG_ROUTER_FLAVOR")
end


local function gen_route(flavor, r)
  if flavor ~= "expressions" then
    return r
  end

  r.expression = atc_compat.get_expression(r)
  r.priority = tonumber(atc_compat._get_priority(r))

  r.destinations = nil

  return r
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
  --- XXX fixme
  local it_not_expressions = (flavor ~= "expressions") and it or pending

for _, strategy in helpers.each_strategy() do
  describe("#stream Proxying [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    reload_router(flavor)

    local bp

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "logger",
      })

      local tcp_srv = bp.services:insert({
        name = "tcp",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_port,
        protocol = "tcp"
      })

      bp.routes:insert(gen_route(flavor, {
        destinations = {
          {
            port = 19000,
          },
        },
        protocols = {
          "tcp",
        },
        service = tcp_srv,
      }))

      local tls_srv = bp.services:insert({
        name = "tls",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_ssl_port,
        protocol = "tls"
      })

      bp.routes:insert(gen_route(flavor, {
        destinations = {
          {
            port = 19443,
          },
        },
        protocols = {
          "tls",
        },
        service = tls_srv,
      }))

      bp.plugins:insert {
        name = "logger",
      }

      assert(helpers.start_kong({
        router_flavor = flavor,
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "logger",
        proxy_listen = "off",
        admin_listen = "off",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                        helpers.get_proxy_ip(false) .. ":19443 ssl"
      }))
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("tcp", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(false), 19000))
      assert(tcp:send(MESSAGE))
      local body = assert(tcp:receive("*a"))
      assert.equal(MESSAGE, body)
      tcp:close()
      wait()
      assert_phases(phases)
    end)

    it_not_expressions("tls", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, nil, false))
      assert(tcp:send(MESSAGE))
      local body = assert(tcp:receive("*a"))
      assert.equal(MESSAGE, body)
      tcp:close()
      wait()
      assert_phases(phases_tls)
    end)
  end)

  describe("#stream Proxying [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    reload_router(flavor)

    local bp

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "logger",
        "short-circuit",
      })

      local tcp_srv = bp.services:insert({
        name = "tcp",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_port,
        protocol = "tcp"
      })

      bp.routes:insert(gen_route(flavor, {
        destinations = {
          {
            port = 19000,
          },
        },
        protocols = {
          "tcp",
        },
        service = tcp_srv,
      }))

      local tls_srv = bp.services:insert({
        name = "tls",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_ssl_port,
        protocol = "tls"
      })

      bp.routes:insert(gen_route(flavor, {
        destinations = {
          {
            port = 19443,
          },
        },
        protocols = {
          "tls",
        },
        service = tls_srv,
      }))

      bp.plugins:insert {
        name = "logger",
      }

      bp.plugins:insert {
        name = "short-circuit",
        config = {
          status = 200,
          message = "plugin executed"
        },
      }

      assert(helpers.start_kong({
        router_flavor = flavor,
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "logger,short-circuit",
        proxy_listen = "off",
        admin_listen = "off",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                        helpers.get_proxy_ip(false) .. ":19443 ssl"
      }))
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("tcp (short-circuited)", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(false), 19000))
      local body = assert(tcp:receive("*a"))
      tcp:close()

      local json = cjson.decode(body)
      assert.same({
        init_worker_called = true,
        message = "plugin executed",
        status = 200
      }, json)

      wait()
      assert_phases(phases_2)
    end)

    it_not_expressions("tls (short-circuited)", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
      assert(tcp:sslhandshake(nil, nil, false))
      local body = assert(tcp:receive("*a"))
      tcp:close()

      local json = assert(cjson.decode(body))
      assert.same({
        init_worker_called = true,
        message = "plugin executed",
        status = 200
      }, json)

      wait()
      assert_phases(phases_tls_2)
    end)
  end)
end
end -- for flavor
