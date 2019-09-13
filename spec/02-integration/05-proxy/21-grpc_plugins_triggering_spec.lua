local helpers = require "spec.helpers"
local pl_file = require "pl.file"


local TEST_CONF = helpers.test_conf



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
    local _, count = logs:gsub([[executing plugin "logger": log]], "")

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

for _, strategy in helpers.each_strategy() do

  describe("gRPC Proxying [#" .. strategy .. "]", function()
    local grpc_client
    local grpcs_client
    local bp

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
        url = "grpc://localhost:15002",
      })

      local service2 = assert(bp.services:insert {
        name = "grpcs",
        url = "grpcs://localhost:15003",
      })

      assert(bp.routes:insert {
        protocols = { "grpc" },
        hosts = { "grpc" },
        service = service1,
      })

      assert(bp.routes:insert {
        protocols = { "grpcs" },
        hosts = { "grpcs" },
        service = service2,
      })

      assert(bp.plugins:insert {
        name = "logger",
      })

      assert(helpers.start_kong {
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
