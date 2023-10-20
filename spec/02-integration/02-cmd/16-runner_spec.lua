-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local helpers = require "spec.helpers"
local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port

local PG_USER = helpers.test_conf.pg_user
local PG_PASSWORD = helpers.test_conf.pg_password
local PG_HOST = helpers.test_conf.pg_host
local PG_PORT = helpers.test_conf.pg_port
local PG_DATABASE = helpers.test_conf.pg_database

describe("kong runner", function()
  local original_prefix

  lazy_setup(function()
    original_prefix = os.getenv("KONG_PREFIX")
    helpers.setenv("KONG_PREFIX", "servroot")
  end)

  lazy_teardown(function()
    if original_prefix then helpers.setenv("KONG_PREFIX", original_prefix) end
  end)

  it("outputs usage", function()
    local _, stderr = helpers.kong_exec("runner --help")
    assert.match_re(stderr, "Usage: kong runner file.lua .*")
  end)

  it("#db postgres connection succeeds", function()
    local connection = PG_HOST .. " " .. PG_PORT .. " " .. PG_DATABASE .. " " ..
                         PG_USER .. " " .. PG_PASSWORD
    local _, _, stdout = helpers.kong_exec(
                           "runner ./scripts/tools/pg.lua " .. connection)
    assert.matches("DB connectivity:", stdout, nil, true)
  end)

  it("#db redis connection succeeds", function()
    local connection = REDIS_HOST .. " " .. REDIS_PORT .. " \"\" false false"
    local _, _, stdout = helpers.kong_exec(
                           "runner ./scripts/tools/redis.lua " .. connection)
    assert.matches("Attempting to write to Redis with", stdout, nil, true)
  end)

  it("tcp connection succeeds", function()
    local _, _, stdout = helpers.kong_exec(
                           "runner ./scripts/tools/tcp_socket.lua konghq.com 443")
    assert.matches("Successfully connected to", stdout, nil, true)
  end)

  it("tcp connection fails", function()
    local _, _, stdout = helpers.kong_exec(
                           "runner ./scripts/tools/tcp_socket.lua konghq.com 444")
    assert.matches("Failed to connect", stdout, nil, true)
  end)

end)

