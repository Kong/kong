-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG


describe("Redis connection pool", function()
  local redis_config_utils, gen_poolname
  local log_spy

  lazy_setup(function()
    log_spy = spy.on(ngx, "log")

    redis_config_utils = require "kong.tools.redis.config_utils"
    gen_poolname = redis_config_utils.gen_poolname
  end)

  lazy_teardown(function()
    log_spy:revert()
  end)

  before_each(function()
    log_spy:clear()
  end)

  it("skip pool name generation if conf is unset", function()
    local conf = {}
    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(ERR, "conf is unset, fallback to default pool")
  end)

  it("skip pool name generation if sentinel_nodes is set", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      sentinel_nodes = {
        { host = "sentinel.test", port = 26379 },
      },
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "sentinel_nodes is set, fallback to default pool")
  end)

  it("skip pool name generation if cluster_nodes is set", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      cluster_nodes = {
        { host = "redis.test", port = 6379 },
      },
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "cluster_nodes is set, fallback to default pool")
  end)

  it("skip pool name generation if host is unset", function()
    local conf = {
      port = 6379,
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "neither host nor socket is set, fallback to default pool")
  end)

  it("skip pool name generation if port is unset", function()
    local conf = {
      host = "redis.test",
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "port is unset, fallback to default pool")
  end)

  it("skip pool name generation if ssl is unset", function()
    local conf = {
      socket = "unix:/tmp/redis.sock",
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "ssl is unset, fallback to default pool")
  end)

  it("skip pool name generation if ssl_verify is unset", function()
    local conf = {
      socket = "unix:/tmp/redis.sock",
      ssl = false,
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "ssl_verify is unset, fallback to default pool")
  end)

  it("skip pool name generation if ssl_verify is true but ssl is not true", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      ssl = false,
      ssl_verify = true,
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "ssl_verify is true but ssl is not true, fallback to default pool")
  end)

  it("skip pool name generation if ssl_verify is true but server_name is unset", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      ssl = true,
      ssl_verify = true,
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "ssl_verify is true but server_name is unset, fallback to default pool")
  end)

  it("skip pool name generation if database is unset", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      ssl = true,
      ssl_verify = true,
      server_name = "redis.test",
    }

    local pool_name = gen_poolname(conf)
    assert.is_nil(pool_name)

    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(DEBUG, "database is unset, fallback to default pool")
  end)

  it("generate pool name 'redis.test:6379::true:true:redis.test:::0'", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      ssl = true,
      ssl_verify = true,
      server_name = "redis.test",
      database = 0,
    }

    local pool_name = gen_poolname(conf)
    assert.equal("redis.test:6379::true:true:redis.test:::0", pool_name)
    assert.spy(log_spy).was_not.called()
  end)

  it("generate pool name '::unix:/tmp/redis.sock:true:false::default:foo:0'", function()
    local conf = {
      socket = "unix:/tmp/redis.sock",
      ssl = true,
      ssl_verify = false,
      username = "default",
      password = "kong",
      database = 0,
    }

    local pool_name = gen_poolname(conf)
    assert.match("::unix:/tmp/redis.sock:true:false::default:%w-:0", pool_name)
    assert.spy(log_spy).was.called()
    assert.spy(log_spy).was.called_with(WARN, "both host and socket are set, prioritize socket")
  end)

  it("generate pool name 'redis.test:6379::false:false:redis.test:::15'", function()
    local conf = {
      host = "redis.test",
      port = 6379,
      ssl = false,
      ssl_verify = false,
      server_name = "redis.test",
      database = 15,
    }

    local pool_name = gen_poolname(conf)
    assert.match("redis.test:6379::false:false:redis.test:::15", pool_name)
    assert.spy(log_spy).was_not.called()
  end)
end)