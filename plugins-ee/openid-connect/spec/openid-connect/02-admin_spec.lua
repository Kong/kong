-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"


local PLUGIN_NAME = "openid-connect"
local JWKS_URI = "/" .. PLUGIN_NAME .. "/jwks"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _ , strategy in strategies() do

describe(JWKS_URI .. "#" .. strategy, function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled," .. PLUGIN_NAME,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end
  end)

  it("returns public keys for all supported algorithms", function()
    local res = admin_client:get(JWKS_URI)
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_table(json)

    local algs = {}

    for _, jwk in ipairs(json.keys) do
      algs[jwk.alg] = true
    end

    assert.same({
      HS256 = true,
      HS384 = true,
      HS512 = true,
      RS256 = true,
      RS512 = true,
      PS256 = true,
      PS384 = true,
      PS512 = true,
      ES256 = true,
      ES384 = true,
      ES512 = true,
      EdDSA = true,
      RS384 = true,
    }, algs)
  end)

  it("removes private keys for all supported algorithms", function()
    local res = admin_client:get(JWKS_URI)
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_table(json)

    for _, jwk in ipairs(json.keys) do
      assert.equal(nil, jwk.k)
      assert.equal(nil, jwk.d)
      assert.equal(nil, jwk.p)
      assert.equal(nil, jwk.dp)
      assert.equal(nil, jwk.dq)
      assert.equal(nil, jwk.qi)
      assert.equal(nil, jwk.oth)
      assert.equal(nil, jwk.r)
      assert.equal(nil, jwk.t)
    end
  end)
end)

end
