local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local atc_compat = require "kong.router.compat"


local TEST_CONF = helpers.test_conf


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

  r.hosts = nil
  r.paths = nil
  r.snis  = nil

  return r
end


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

-- Phrases and counters for unary grpc requests **without reflection**,
-- Phrases with a -1 count are checked to have at least one occurrence

local phrases = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] rewrite phase"] = 1,
  ["%[logger%] access phase"] = 1,
  ["%[logger%] header_filter phase"] = 1,
  ["%[logger%] body_filter phase"] = -1,
  ["%[logger%] log phase"] = 1,
}

local phrases_ssl = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] certificate phase"] = 1,
  ["%[logger%] rewrite phase"] = 1,
  ["%[logger%] access phase"] = 1,
  ["%[logger%] header_filter phase"] = 1,
  ["%[logger%] body_filter phase"] = -1,
  ["%[logger%] log phase"] = 1,
}

-- Phrases and counters for unary grpc requests **with reflection**,
-- Phrases with a -1 count are checked to have at least one occurrence
--
-- "Reflection" is a gRPC server extension to assist clients without prior
-- prior knowledge of the server's services methods and messages formats.
--
-- A request sent to method `/hello.HelloService/SayHello` without a protobuf
-- file will result in two requests, resembling the following:
--   /grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo
--     (obtain methods and data formats)
--   /hello.HelloService/SayHello
--     (perform actual intended request)

local phrases_reflection = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] rewrite phase"] = 2,
  ["%[logger%] access phase"] = 2,
  ["%[logger%] header_filter phase"] = 2,
  ["%[logger%] body_filter phase"] = -1,
  ["%[logger%] log phase"] = 2,
}

local phrases_ssl_reflection = {
  ["%[logger%] init_worker phase"] = 1,
  ["%[logger%] certificate phase"] = 1,
  ["%[logger%] rewrite phase"] = 2,
  ["%[logger%] access phase"] = 2,
  ["%[logger%] header_filter phase"] = 2,
  ["%[logger%] body_filter phase"] = -1,
  ["%[logger%] log phase"] = 2,
}

local function assert_phases(phrases)
  for phase, count in pairs(phrases) do
    assert(find_in_file(phase, count))
  end
end

for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, strategy in helpers.each_strategy() do

  describe("gRPC Proxying [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    local grpc_client
    local grpcs_client
    local bp

    reload_router(flavor)

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "logger",
      })

      local service1 = assert(bp.services:insert {
        name = "grpc",
        url = helpers.grpcbin_url,
      })

      local service2 = assert(bp.services:insert {
        name = "grpcs",
        url = helpers.grpcbin_ssl_url,
      })

      assert(bp.routes:insert(gen_route(flavor, {
        protocols = { "grpc" },
        hosts = { "grpc" },
        service = service1,
      })))

      assert(bp.routes:insert(gen_route(flavor, {
        protocols = { "grpcs" },
        hosts = { "grpcs" },
        service = service2,
      })))

      assert(bp.plugins:insert {
        name = "logger",
      })

      assert(helpers.start_kong {
        router_flavor = flavor,
        database = strategy,
        plugins = "logger",
      })

      grpc_client = assert(helpers.proxy_client_grpc())
      grpcs_client = assert(helpers.proxy_client_grpcs())
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("grpc", function()
      local ok, resp = grpc_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpc",
        },
      })
      assert.truthy(ok)
      assert.truthy(resp)

      wait()

      assert_phases(phrases)
    end)

    it("grpcs", function()
      local ok, resp = grpcs_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpcs",
        },
      })
      assert(ok)
      assert.truthy(resp)
      wait()

      assert_phases(phrases_ssl)
    end)

    it("grpc - with reflection", function()
      local ok, resp = grpc_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpc",
          ["-proto"] = false,
        },
      })
      assert(ok)
      assert.truthy(resp)
      wait()

      assert_phases(phrases_reflection)
    end)

    it("grpcs - with reflection", function()
      local ok, resp = grpcs_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpcs",
          ["-proto"] = false,
        },
      })
      assert.truthy(ok)
      assert.truthy(resp)
      wait()

      assert_phases(phrases_ssl_reflection)
    end)
  end)
end
end   -- flavor
