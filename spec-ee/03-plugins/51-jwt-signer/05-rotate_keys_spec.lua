-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local jws = require "kong.openid-connect.jws"
local jwks = require "kong.openid-connect.jwks"
local json = require "cjson.safe"
local fmt = string.format
local plugin_name = "jwt-signer"
local cache = require "kong.plugins.jwt-signer.cache"
local time = ngx.time

describe(fmt("%s - is_rotated_recently", plugin_name), function()
  it("should return the elapsed time if the jwks were rotated recently", function()
    local now = time()
    local row = {
      name = "foo-jwks",
      keys = assert(jwks.new({ unwrap = true, json = false })),
      created_at = now,
      updated_at = now,
    }

    local res = cache.is_rotated_recently(row, 300)
    assert(res)
    assert(res < 300)
  end)

  it("should return nil if the jwks were not rotated recently", function()
    local now = time()
    local row = {
      name = "foo-jwks",
      keys = assert(jwks.new({ unwrap = true, json = false })),
      created_at = now - 600,
      updated_at = now - 600,
    }

    local res = cache.is_rotated_recently(row, 300)
    assert.is_nil(res)
  end)
end)

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - load/rotate jwks [#%s]", plugin_name, strategy), function()
    local bp, db, admin_client, proxy_client

    local HTTP_SERVER_PORT = helpers.get_available_port()
    local jwks_uri = "http://localhost:" .. HTTP_SERVER_PORT .. "/jwks"
    local bad_jwks_uri = "http://localhost:" .. HTTP_SERVER_PORT .. "/bad_jwks"
    local ec_key = '{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","kid":"19J8y7Zprt2-QKLjF2I5pVk0OELX6cY2AfaAv1LC_w8","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}'
    local keyset_name = "kong"

    local now = ngx.time()
    local exp = now + 600
    local token = {
      jwk = json.decode(ec_key),
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
    local access_token = assert(jws.encode(token))
    local credential = "Bearer " .. access_token

    local mock = http_mock.new(HTTP_SERVER_PORT, {
      ["/jwks"] = {
        access = [[
          package.path = package.path ..  ";/usr/local/share/lua/5.1/?.ljbc;/usr/local/share/lua/5.1/?/init.ljbc"
          local jwks = require "kong.openid-connect.jwks"
          local keys_json, err = jwks.new({ json = true })
          if not keys_json then
            print(err)
            ngx.exit(500)
          end

          ngx.header.content_type = "application/jwk-set+json"
          ngx.print(keys_json)
          ngx.exit(200)
        ]]
      },
      ["/bad_jwks"] = {
        access = [[
          local count = ngx.bad_jwks_count or 0
          ngx.bad_jwks_count = count + 1

          if count % 2 == 0 then
            ngx.exit(500)
          end

          local keys_json = '{"keys": [  ]] .. ec_key .. [[ ]}'
          ngx.header.content_type = "application/jwk-set+json"
          ngx.print(keys_json)
          ngx.exit(200)
        ]]
      },
    })

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
        "jwt_signer_jwks",
      }, { plugin_name })

      local route1 = bp.routes:insert({ paths = { "/uri" } })
      local route2 = bp.routes:insert({ paths = { "/bad_uri" } })
      local route3 = bp.routes:insert({ paths = { "/keyset" } })

      bp.plugins:insert({
        name = plugin_name,
        route = route1,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri,
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = bad_jwks_uri,
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization:Bearer",
          access_token_keyset = keyset_name,
          channel_token_optional = true,
        },
      })

      assert(mock:start())
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      assert(db:truncate("jwt_signer_jwks"))
      assert(db:truncate("plugins"))
      assert(db:truncate("services"))
      assert(db:truncate("routes"))
      helpers.stop_kong()
      mock:stop()
    end)

    describe("load keys", function()
      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        helpers.clean_logfile()
        if proxy_client then
          proxy_client:close()
        end
      end)

      it("fallback to empty jwks and trigger rediscovery", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/bad_uri",
          headers = {
            ["Authorization"] = credential,
          }
        })
        assert.response(res).has.status(401)
        assert.logfile().has.line("loading jwks from " .. bad_jwks_uri, true)
        assert.logfile().has.line("falling back to empty jwks", true)
        assert.logfile().has.line("rediscovering keys for " .. bad_jwks_uri, true)
        assert.logfile().has.line("jwks were rotated less than 5 minutes ago (skipping)", true)
        assert.logfile().has.line("suitable jwk was not found", true)
      end)

      it("should succeed to authenticate", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/bad_uri",
          headers = {
            ["Authorization"] = credential,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.line("loading jwks from " .. bad_jwks_uri, true)
      end)

      it("use the cached jwks, won't load new jwks", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/bad_uri",
          headers = {
            ["Authorization"] = credential,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.no.line("loading jwks from " .. bad_jwks_uri, true)
      end)

      it("should succeed to resign by using the keyset", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/keyset",
          headers = {
            ["Authorization"] = credential,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.line("creating jwks for kong", true)
      end)
    end)

    describe("rotate keys", function()
      before_each(function()
        admin_client = helpers.admin_client()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        helpers.clean_logfile()
        if admin_client then
          admin_client:close()
        end
        if proxy_client then
          proxy_client:close()
        end
      end)

      if strategy ~= "off" then
        for name, path in pairs({[jwks_uri] = "/uri", [keyset_name] = "/keyset"}) do
          it("rotate jwks " .. name, function()
            local urlencoded_name = ngx.escape_uri(name)

            -- load once first to make sure the jwks exists
            assert(proxy_client:send {
              method = "GET",
              path = path,
              headers = {
                ["Authorization"] = credential, -- arbitrary credential just to trigger loading
              }
            })

            -- rotate the jwks
            local res, err = assert(admin_client:send {
              method = "POST",
              path = fmt("/jwt-signer/jwks/%s/rotate", urlencoded_name)
            })
            assert.is_nil(err)
            local body = assert.res_status(200, res)
            local old_keys = json.decode(body)
            assert.logfile().has.line("rotating jwks for " .. name, true)

            -- rotate the jwks again (forcibly)
            res, err = assert(admin_client:send {
              method = "POST",
              path = fmt("/jwt-signer/jwks/%s/rotate", urlencoded_name)
            })
            assert.is_nil(err)
            body = assert.res_status(200, res)
            local new_keys = json.decode(body)
            assert.logfile().has.line("rotating jwks for " .. name, true)
            assert.is_same(new_keys.previous, old_keys.keys)
            assert.is_not_same(new_keys.keys, old_keys.keys)
          end)
        end
      end
    end)
  end)
end
