-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local helpers = require "spec.helpers"
local jwe     = require "kong.pdk.jwe".new()
local merge   = kong.table.merge
local cjson   = require "cjson.safe"
local fmt     = string.format

local PLUGIN_NAME = "jwe-decrypt"
local KEY_SET_NAME = "test"
local jwt_enc
local PLAINTEXT = "testing cipher"

local content_encryption_algs = {
  "A256GCM"
}

local key_encryption_algs = {
  "RSA-OAEP"
}

-- Run tests with a combination of supported content and key encryption algorithms
for _, strategy in helpers.each_strategy({ "postgres", "off" }) do
  for _, enc in ipairs(content_encryption_algs) do
    for _, alg in ipairs(key_encryption_algs) do
      local description = string.format("alg=%s enc=%s", alg, enc)
      describe("JWE Decryption Plugin " .. description .. " # " .. strategy, function()
        local proxy_client
        local admin_client
        local err_log_file
        local pem_pub, pem_priv

        lazy_setup(function()
          local bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
            "keys",
            "key_sets"
          }, {PLUGIN_NAME})


          local jwk_pub, jwk_priv = helpers.generate_keys("JWK")
          pem_pub, pem_priv = helpers.generate_keys("PEM")

          local jwk_raw = merge(cjson.decode(jwk_pub), cjson.decode(jwk_priv))
          -- overwrite kid with something predictable.
          jwk_raw.kid = "42"
          local key_sets, key_sets_err = db.key_sets:insert({
            name = KEY_SET_NAME,
          })
          assert.is_nil(key_sets_err)
          assert.is_not_nil(key_sets)
          local jwk_key, err = db.keys:insert({
            name = "jwk RSA key",
            jwk = cjson.encode(jwk_raw),
            kid = jwk_raw.kid,
            set = key_sets
          })
          assert.is_nil(err)
          assert.is_not_nil(jwk_key)
          local pem_key, p_err = db.keys:insert({
            name = "pem RSA key",
            pem = {
              private_key = pem_priv,
              public_key = pem_pub
            },
            set = key_sets,
            kid = "666"
          })
          assert.is_nil(p_err)
          assert.is_not_nil(pem_key)

          local enc_err
          jwt_enc, enc_err = jwe:encrypt(alg, enc, cjson.decode(jwk_key.jwk), PLAINTEXT)
          assert.is_nil(enc_err)
          assert(jwt_enc)

          local route1 = bp.routes:insert({
            hosts = { "test1.test" },
          })

          local route2 = bp.routes:insert({
            hosts = { "test2.test" },
          })
          local route3 = bp.routes:insert({
            hosts = { "test3.test" },
          })
          local route4 = bp.routes:insert({
            hosts = { "test4.test" },
          })
          local route5 = bp.routes:insert({
            hosts = { "test5.test" },
          })

          bp.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route1.id },
            config = {
              key_sets = { KEY_SET_NAME },
            }
          }
          bp.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route2.id },
            config = {
              key_sets = { KEY_SET_NAME },
              lookup_header_name = "test_header_name"
            }
          }
          bp.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route3.id },
            config = {
              key_sets = { KEY_SET_NAME },
              forward_header_name = "test_upstream_header"
            }
          }
          bp.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route4.id },
            config = {
              key_sets = { "not-found" },
            }
          }
          bp.plugins:insert {
            name = PLUGIN_NAME,
            route = { id = route5.id },
            config = {
              key_sets = { KEY_SET_NAME },
              strict = false,
            }
          }
          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins    = "bundled," .. PLUGIN_NAME
          }))
          err_log_file = helpers.test_conf.nginx_err_logs
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          proxy_client = helpers.proxy_client()
          admin_client = helpers.admin_client()
        end)

        after_each(function()
          if admin_client then
            admin_client:close()
          end
          if proxy_client then
            proxy_client:close()
          end
        end)

        it("decrypts properly", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request", -- makes mockbin return the entire request
            headers = {
              host = "test1.test",
              ["Authorization"] = jwt_enc
            }
          })
          assert.logfile(err_log_file).has.line("setting decrypted JWE to header")
          assert.response(res).has.status(200)
          local val = assert.request(res).has.header("authorization")
          assert.equal(PLAINTEXT, val)
        end)

        -- https://www.rfc-editor.org/rfc/rfc6750.html#section-2.1
        it("decrypts properly with Bearer token", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request", -- makes mockbin return the entire request
            headers = {
              host = "test1.test",
              ["Authorization"] = fmt("Bearer %s", jwt_enc)
            }
          })
          assert.response(res).has.status(200)
          local val = assert.request(res).has.header("authorization")
          assert.equal("Bearer " .. PLAINTEXT, val)
          assert.logfile(err_log_file).has.line("setting decrypted JWE to header")
        end)

        it("decrypts and respects lookup_header_name config", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test2.test",
              ["test_header_name"] = jwt_enc
            }
          })
          assert.response(res).has.status(200)
          assert.logfile(err_log_file).has.line("setting decrypted JWE to header")
          local val = assert.request(res).has.header("authorization")
          assert.equal(PLAINTEXT, val)
        end)

        it("decrypts and respects forward_header_name config", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test3.test",
              ["Authorization"] = jwt_enc
            }
          })
          assert.response(res).has.status(200)
          local val = assert.request(res).has.header("test_upstream_header")
          assert.equal(PLAINTEXT, val)
        end)

        it("logs and aborts if set was not found", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test4.test",
              ["Authorization"] = jwt_enc
            }
          })
          assert.logfile(err_log_file).has.line("could not load keyset")
          assert.response(res).has_not.header("test-upstream-header")
          assert.response(res).has.status(403)
        end)

        it("logs and aborts if header was not found", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test4.test",
            }
          })
          assert.logfile(err_log_file).has.line("could not find header")
          assert.response(res).has_not.header("test-upstream-header")
          assert.response(res).has.status(403)
        end)

        it("logs if header was not found but succeeds [strict=false]", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test5.test",
            }
          })
          assert.logfile(err_log_file).has.line("could not find header")
          assert.response(res).has_not.header("test-upstream-header")
          assert.response(res).has.status(200)
        end)

        it("logs and aborts if token could not be decoded (is no JWE)", function()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/request",
            headers = {
              host = "test1.test",
              ["Authorization"] = "no-jwt"
            }
          })
          assert.logfile(err_log_file).has.line("unable to json decode")
          assert.response(res).has_not.header("test-upstream-header")
          assert.response(res).has.status(400)
        end)
      end)
    end
  end
end
