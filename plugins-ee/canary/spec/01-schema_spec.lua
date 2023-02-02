-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"
local validate_entity = require("spec.helpers").validate_plugin_config_schema
local canary_schema = require "kong.plugins.canary.schema"

local ngx = ngx


describe("canary schema", function()
  it("should work with all require fields provided(default start time)", function()
    local ok, err = validate_entity({ upstream_host = "balancer_a" }, canary_schema)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("should work with all require fields provided(fixed percentage)", function()
    local ok, err = validate_entity({ percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time())
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time()) - 1000
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.is_falsy(ok)
    assert.is_same("'start' cannot be in the past", err.config.start)
  end)
  it("hash set as `ip`", function()
    local ok, err = validate_entity({ hash = "ip", percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("hash set as `header`", function()
    local ok, err = validate_entity({
      hash = "header",
      percentage = 10,
      upstream_host = "balancer_a",
      hash_header = "X-My-Header",
    }, canary_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
  it("hash set as `header` requires 'hash_header'", function()
    local ok, err = validate_entity({ hash = "header", percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_same({
      ["@entity"] = {
        [1] = "failed conditional validation given value of field 'config.hash'" },
      ["config"] = {
        ["hash_header"] = 'required field missing' } }, err)
    assert.is_falsy(ok)
  end)
  it("hash set as `none`", function()
    local ok, err = validate_entity({ hash = "none", percentage = 10, upstream_host = "balancer_a" },
      canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("validate duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value must be greater than 0", err.config.duration)
  end)
  it("validate negative duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value must be greater than 0", err.config.duration)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = -1,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 100", err.config.percentage)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = 101,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 100", err.config.percentage)
  end)
  it("validate upstream_host", function()
    local upstream_host = "htt://example.com";
    local ok, err = validate_entity({ percentage = "10", upstream_host = upstream_host },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("invalid value: " .. upstream_host, err.config.upstream_host)
  end)
  it("validate upstream_port", function()
    local ok, err = validate_entity({ percentage = 10, upstream_port = 100 }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("validate upstream_port out of range", function()
    local ok, err = validate_entity({ percentage = 10, upstream_port = 100000 }, canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 65535", err.config.upstream_port)
  end)
  it("validate upstream_uri", function()
    local ok, err = validate_entity({ percentage = 10, upstream_uri = "/" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("upstream_host or upstream_uri must be provided", function()
    local ok, err = validate_entity({}, canary_schema)

    assert.is_falsy(ok)
    local expected = {
      "at least one of these fields must be non-empty: 'config.upstream_uri', 'config.upstream_host', 'config.upstream_port'",
    }
    assert.is_same(expected, err["@entity"])
  end)
  it("upstream_fallback requires upstream_host", function()
    local ok, err = validate_entity({upstream_fallback = true, upstream_port = 8080}, canary_schema)

    assert.is_falsy(ok)
    local expected = {
      "failed conditional validation given value of field 'config.upstream_fallback'",
    }
    assert.is_same(expected, err["@entity"])
  end)
  it("validates what looks like a domain", function()
    local ok, err = validate_entity({ percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy
  for _, strategy in strategies() do
    describe("strategy: [#" .. strategy .. "]", function ()
      local proxy_client, admin_client, admin_client_2
      local route1
      local db_strategy = strategy ~= "off" and strategy or nil
      setup(function()
        local bp = helpers.get_db_utils(db_strategy, nil, {
          "canary"
        })
        route1 = bp.routes:insert({
          hosts = { "canary1.com" },
          preserve_host = false,
        })
        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = db_strategy,
          plugins = "canary",
        }, nil, nil))
      end)

      teardown(function()
        helpers.stop_kong(nil, true)
      end)


      before_each(function()
        proxy_client = helpers.proxy_client()
        admin_client = helpers.admin_client()
        admin_client_2 = helpers.admin_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
        if admin_client then
          admin_client:close()
        end
      end)

      it("will add default value for start time", function ()
        local tstart = ngx.time()
        assert(admin_client:send {
          method = "POST",
          path = "/routes/" .. route1.id .."/plugins",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "canary",
            config = { upstream_host = "balancer_a" },
          }
        })

        local res = assert(admin_client_2:send {
          method = "GET",
          path = "/routes/" .. route1.id .."/plugins",
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- check if start time is set to current time
        local within_current_time = json.data[1].config.start - tstart < 3
        assert.True(within_current_time)
      end)
    end)
  end
end)
