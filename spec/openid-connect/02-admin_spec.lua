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


describe(JWKS_URI, function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils("postgres", nil, { PLUGIN_NAME })

    assert(helpers.start_kong({
      database   = "postgres",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled," .. PLUGIN_NAME,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
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

    for i, jwk in ipairs(json.keys) do
      algs[i] = jwk.alg
    end

    assert.same({
      "HS256",
      "HS384",
      "HS512",
      "RS256",
      "RS512",
      "PS256",
      "PS384",
      "PS512",
      "ES256",
      "ES384",
      "ES512",
      "EdDSA",
    }, algs)
  end)

end)
