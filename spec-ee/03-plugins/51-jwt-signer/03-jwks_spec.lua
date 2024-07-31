-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = "jwt-signer"
local helpers = require "spec.helpers"
local jws = require "kong.openid-connect.jws"
local fmt = string.format
local cjson = require "cjson"

local function find_keyset_by_name(adc, name)
  local res, err = assert(adc:send {
    method = "GET",
    path = fmt("/jwt-signer/jwks")
  })
  assert.is_nil(err)
  local body = assert.res_status(200, res)
  local keysets = cjson.decode(body)
  for _, data in ipairs(keysets.data) do
    if data.name == name then
      return data, data.id
    end
  end
  return nil
end

for _, strategy in helpers.each_strategy({ "postgres", "off" }) do
  describe(fmt("%s - auto-generated jwks", plugin_name), function()
    local _, db, admin_client, keyset_name
    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()

      keyset_name = "kong"

      local res, err = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body    = {
          name  = plugin_name,
          config = {
            access_token_keyset = keyset_name
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.is_nil(err)
      assert.res_status(201, res)
    end)

    lazy_teardown(function()
      assert(db:truncate("jwt_signer_jwks"))
      assert(db:truncate("plugins"))
      if admin_client then admin_client:close() end
      helpers.stop_kong()
    end)

    it("get created when access_token_keyset is not a URL", function()
      local res, err = assert(admin_client:send {
        method = "GET",
        path = "/jwt-signer/jwks"
      })
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.data[1].keys)
      assert.is_table(json.data[1].keys[1])
    end)

    it("can be queried by name", function()
      local res, err = assert(admin_client:send {
        method = "GET",
        path = fmt("/jwt-signer/jwks/%s", keyset_name)
      })
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.keys[1])
    end)

    it("can be rotated", function()
      local res, err = assert(admin_client:send {
        method = "GET",
        path = fmt("/jwt-signer/jwks/%s", keyset_name)
      })
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local current_keys = cjson.decode(body)
      -- rotate the keyset
      local r_res, r_err = assert(admin_client:send {
        method = "POST",
        path = fmt("/jwt-signer/jwks/%s/rotate", keyset_name)
      })
      assert.is_nil(r_err)
      local r_body = assert.res_status(200, r_res)
      local rotated_keys = cjson.decode(r_body)
      assert.is_same(rotated_keys.previous, current_keys.keys)
      assert.is_not_same(rotated_keys.keys, current_keys.keys)
    end)

    it("can be deleted", function()
      local d_res, d_err = assert(admin_client:send {
        method = "DELETE",
        path = fmt("/jwt-signer/jwks/%s", keyset_name)
      })
      assert.is_nil(d_err)
      assert.res_status(204, d_res)
      local g_res, err = assert(admin_client:send {
        method = "GET",
        path = fmt("/jwt-signer/jwks/%s", keyset_name)
      })
      assert.is_nil(err)
      -- keys should be gone
      assert.res_status(404, g_res)
    end)
  end)

  describe(fmt("%s - jwks by URL", plugin_name), function()
    local _, db, admin_client
    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      db:truncate("plugins")
      db:truncate("jwt_signer_jwks")
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      helpers.stop_kong()
    end)

    it("does not create a keyset when access_token_keyset is a URL and there are no keys behind this URL", function()
      local url = "http://my-jwks.xyz"
      local res, err = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body    = {
          name  = plugin_name,
          config = {
            access_token_keyset = url
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.is_nil(err)
      assert.res_status(201, res)
      local keyset = find_keyset_by_name(admin_client, url)
      -- it must not find one as the url does not expose JWKs
      assert.is_nil(keyset)
    end)

    it("sources keyset when access_token_keyset is a URL containing keys", function()
      local url = "https://www.googleapis.com/oauth2/v3/certs"
      local res, err = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body    = {
          name  = plugin_name,
          config = {
            access_token_keyset = url
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.is_nil(err)
      assert.res_status(201, res)
      local keyset, id = find_keyset_by_name(admin_client, url)
      assert.is_table(keyset)
      local res1, err1 = assert(admin_client:send {
        method = "GET",
        path = fmt("/jwt-signer/jwks/%s", tostring(id))
      })
      assert.is_nil(err1)
      local body = assert.res_status(200, res1)
      local json = cjson.decode(body)
      assert.is_table(json.keys)
      assert.is_not_same(json.keys, {})
    end)

    it("rotating sourced keys", function()
      local url = "https://www.googleapis.com/oauth2/v3/certs"
      local res, err = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body    = {
          name  = plugin_name,
          config = {
            access_token_keyset = url
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.is_nil(err)
      assert.res_status(201, res)
      local _, id = find_keyset_by_name(admin_client, url)
      assert.is_not_nil(id)
      local res1, err1 = assert(admin_client:send {
        method = "GET",
        path = fmt("/jwt-signer/jwks/%s", tostring(id))
      })
      assert.is_nil(err1)
      local body = assert.res_status(200, res1)
      local current_keys = cjson.decode(body)
      assert.is_table(current_keys.keys)
      assert.is_not_same(current_keys.keys, {})
      local r_res, r_err = assert(admin_client:send {
        method = "POST",
        path = fmt("/jwt-signer/jwks/%s/rotate", tostring(id))
      })
      assert.is_nil(r_err)
      local r_body = assert.res_status(200, r_res)
      local rotated_keys = cjson.decode(r_body)
      -- check that position changed (not necessarily the content as this is an externally managed jwks endpoint)
      assert.is_same(rotated_keys.previous, current_keys.keys)
    end)

  end)
end

describe(fmt("%s - dbless specific tests", plugin_name), function()
  local bp, db, admin_client, proxy_client, keyset_name, yaml_file
  local ec_key = '{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","kid":"19J8y7Zprt2-QKLjF2I5pVk0OELX6cY2AfaAv1LC_w8","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}'
  local now = ngx.time()
  local exp = now + 600
  local token = {
    jwk = cjson.decode(ec_key),
    header = {
      typ = "JWT",
      alg = "ES256",
    },
    payload = {
      sub = "1234567890",
      name = "John Doe",
      exp = exp,
      now = now,
    },
  }
  keyset_name = "kong"

  lazy_setup(function()
    bp, db = helpers.get_db_utils("postgres", {
      "routes",
      "services",
      "plugins",
      "jwt_signer_jwks",
    }, { plugin_name })

    local route = bp.routes:insert({ paths = { "/keyset" } })

    bp.plugins:insert({
      name = plugin_name,
      route = route,
      config = {
        verify_access_token_signature = false,
        access_token_signing_algorithm = "ES256",
        access_token_upstream_header = "Authorization:Bearer",
        access_token_keyset = keyset_name,
        channel_token_optional = true,
      }
    })

    yaml_file = helpers.make_yaml_file()

    assert(helpers.start_kong({
      database   = "off",
      plugins    = plugin_name,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      declarative_config = yaml_file,
      pg_host = "unknownhost.konghq.com",
    }))
  end)

  lazy_teardown(function()
    assert(db:truncate("jwt_signer_jwks"))
    assert(db:truncate("plugins"))
    assert(db:truncate("services"))
    assert(db:truncate("routes"))
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
    proxy_client = helpers.proxy_client()
  end)

  after_each(function()
    if admin_client then admin_client:close() end
    if proxy_client then proxy_client:close() end
  end)

  it("can be queried by name", function()
    local access_token = assert(jws.encode(token))
    local credential = "Bearer " .. access_token

    -- load once first to make sure the jwks exists
    assert(proxy_client:send {
      method = "GET",
      path = "/keyset",
      headers = {
        ["Authorization"] = credential,
      }
    })

    local res, err = assert(admin_client:send {
      method = "GET",
      path = fmt("/jwt-signer/jwks/%s", ngx.escape_uri(keyset_name))
    })
    assert.is_nil(err)
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_table(json.keys[1])
  end)
end)
