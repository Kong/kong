-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local merge = kong.table.merge

local HEADERS = { ["Content-Type"] = "application/json" }
local KEY_SET_NAME = "test"

for _, strategy in helpers.all_strategies() do
  describe("Admin API - keys #" .. strategy, function()
    local db, bp
    local pem_pub, pem_priv, jwk
    helpers.setenv("SECRET_JWK", '{"alg": "RSA-OAEP", "kid": "test"}')
    local client
    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "keys",
        "key_sets" })

      local jwk_pub, jwk_priv = helpers.generate_keys("JWK")
      pem_pub, pem_priv = helpers.generate_keys("PEM")

      jwk = merge(cjson.decode(jwk_pub), cjson.decode(jwk_priv))

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled",
        nginx_http_include = "../spec/fixtures/jwks/jwks.conf",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("/key-sets/:key-set/rotate", function()
      lazy_teardown(function()
        db:truncate("key_sets")
        db:truncate("keys")
      end)

      it("needs to update keys when remote keys have changed", function()
        -- the used URI `simulate_key_rotation` returns alternating
        -- key-sets to simulate keys being changed.
        -- check kong/spec/fixtures/jwks/mocks.lua for details
        local res = assert(client:post("/key-sets", {
          headers = HEADERS,
          body = {
            name = "test_jwks",
            jwks_url = "http://localhost:9543/simulate_key_rotation"
          }
        }))
        assert.res_status(201, res)
        local keys, err = assert(client:get("/key-sets/test_jwks/keys"))
        assert.is_nil(err)
        local body = assert.res_status(200, keys)
        local pre_rotate = cjson.decode(body)
        -- The fixture exposes 2 keys
        assert(#pre_rotate, 2)
        -- initiate rotation
        local rotate_ok, rotate_err = assert(client:patch("/key-sets/test_jwks/rotate"))
        local r_body = assert.res_status(200, rotate_ok)
        assert.is_nil(rotate_err)
        local j_body = cjson.decode(r_body)
        -- expect success
        assert(j_body.message == true)

        -- check rotated keys
        local new_keys, new_err = assert(client:get("/key-sets/test_jwks/keys"))
        assert.is_nil(new_err)
        local new_body = assert.res_status(200, new_keys)
        local post_rotate = cjson.decode(new_body)
        -- do we still have 2 keys
        assert(#post_rotate, 2)
        assert.same(#post_rotate, #pre_rotate)
        -- they should NOT be the same
        table.sort(pre_rotate, function(a, b) return a.kid > b.kid end)
        table.sort(post_rotate, function(a, b) return a.kid > b.kid end)
        assert.not_same(pre_rotate, post_rotate)
      end)

      it("must not update keys when remote keys have not changed", function()
        local res = assert(client:post("/key-sets", {
          headers = HEADERS,
          body = {
            name = "persistent_keys",
            jwks_url = "http://localhost:9543/google_jwks"
          }
        }))
        assert.res_status(201, res)
        local keys, err = assert(client:get("/key-sets/persistent_keys/keys"))
        assert.is_nil(err)
        local body = assert.res_status(200, keys)
        local pre_rotate = cjson.decode(body)
        -- The fixture exposes 2 keys
        assert(#pre_rotate, 2)
        -- initiate rotation
        local rotate_ok, rotate_err = assert(client:patch("/key-sets/persistent_keys/rotate"))
        local r_body = assert.res_status(200, rotate_ok)
        assert.is_nil(rotate_err)
        local j_body = cjson.decode(r_body)
        -- expect success
        assert(j_body.message == true)

        -- check rotated keys
        local new_keys, new_err = assert(client:get("/key-sets/persistent_keys/keys"))
        assert.is_nil(new_err)
        local new_body = assert.res_status(200, new_keys)
        local post_rotate = cjson.decode(new_body)
        -- do we still have 2 keys
        assert(#post_rotate, 2)
        assert.same(#post_rotate, #pre_rotate)
        -- they should be _contentual_ the same
        table.sort(pre_rotate, function(a, b) return a.kid > b.kid end)
        table.sort(post_rotate, function(a, b) return a.kid > b.kid end)
        assert.same(pre_rotate, post_rotate)
      end)

      it("needs to return meaningful error messages", function()
        local res = assert(client:post("/key-sets", {
          headers = HEADERS,
          body = {
            name = "no_keys",
            jwks_url = "http://localhost:9543/no-jwks"
          }
        }))
        local body = assert.res_status(400, res)
        local err = cjson.decode(body)
        assert.same(err.message, "schema violation (1: could not retrieve keys from the remote resource)")
      end)
    end)

    describe("setup keys and key-sets", function()
      lazy_teardown(function()
        db:truncate("key_sets")
        db:truncate("keys")
      end)

      local test_jwk_key, test_pem_key
      local test_key_set
      lazy_setup(function()
        local r_key_set = helpers.admin_client():post("/key-sets", {
          headers = HEADERS,
          body = {
            name = KEY_SET_NAME,
          },
        })
        local body = assert.res_status(201, r_key_set)
        local key_set = cjson.decode(body)
        test_key_set = key_set

        local j_key = helpers.admin_client():post("/keys", {
          headers = HEADERS,
          body = {
            name = "unique jwk key",
            set = { id = key_set.id },
            jwk = cjson.encode(jwk),
            kid = jwk.kid
          }
        })
        local key_body = assert.res_status(201, j_key)
        test_jwk_key = cjson.decode(key_body)
        local p_key = helpers.admin_client():post("/keys", {
          headers = HEADERS,
          body = {
            name = "unique pem key",
            set = { id = key_set.id },
            pem = {
              public_key = pem_pub,
              private_key = pem_priv,
            },
            kid = "test_pem"
          }
        })
        local p_key_body = assert.res_status(201, p_key)
        test_pem_key = cjson.decode(p_key_body)
      end)

      describe("POST /key-sets and /keys", function()
        it("create pem key without set", function()
          local p_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "pemkey no set",
              pem = {
                public_key = pem_pub,
                private_key = pem_priv,
              },
              kid = "test_pem_no_set"
            }
          })
          local p_key_body = assert.res_status(201, p_key)
          test_pem_key = cjson.decode(p_key_body)
        end)

        it("create pem key without set", function()
          local j_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "jwk no set",
              jwk = cjson.encode(jwk),
              kid = jwk.kid
            }
          })
          local key_body = assert.res_status(201, j_key)
          test_jwk_key = cjson.decode(key_body)
        end)

        it("create invalid JWK", function()
          local j_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "jwk invalid",
              jwk = '{"kid": "36"}',
              kid = "36"
            }
          })
          local key_body = assert.res_status(400, j_key)
          local jwk_key = cjson.decode(key_body)
          assert.equal('schema violation (could not load JWK, likely not a valid key)', jwk_key.message)
        end)
      end)


      describe("GET /key-sets and /keys", function()
        it("retrieves all key-sets and keys configured", function()
          local res = client:get("/key-sets")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.data)
          local _res = client:get("/keys")
          local _body = assert.res_status(200, _res)
          local _json = cjson.decode(_body)
          assert.equal(4, #_json.data)
        end)
      end)

      describe("PATCH /key-sets and /keys", function()
        it("updates a key-set by id", function()
          local res = client:patch("/key-sets/" .. test_key_set.id, {
            headers = HEADERS,
            body = {
              name = "changeme"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("changeme", json.name)
        end)

        it("updates a jwk key by id", function()
          local res = client:patch("/keys/" .. test_jwk_key.id, {
            headers = HEADERS,
            body = {
              name = "changeme_jwk"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("changeme_jwk", json.name)
        end)

        it("updates a pem key by id", function()
          local res = client:patch("/keys/" .. test_pem_key.id, {
            headers = HEADERS,
            body = {
              name = "changeme_pem"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("changeme_pem", json.name)
        end)
      end)

      describe("DELETE /key-sets and /keys", function()
        it("cascade deletes keys when key-set is deleted", function()
          -- assert we have 1 key-sets
          local res = client:get("/key-sets/")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.data)
          -- assert we have 4 key
          local res_ = client:get("/keys")
          local body_ = assert.res_status(200, res_)
          local json_ = cjson.decode(body_)
          assert.equal(4, #json_.data)

          local d_res = client:delete("/key-sets/" .. json.data[1].id)
          assert.res_status(204, d_res)

          -- assert keys assinged to the key-set were deleted (by cascade)
          local _res = client:get("/keys")
          local _body = assert.res_status(200, _res)
          local _json = cjson.decode(_body)
          assert.equal(2, #_json.data)

          -- assert key-sets were deleted
          local __res = client:get("/key-sets")
          local __body = assert.res_status(200, __res)
          local __json = cjson.decode(__body)
          assert.equal(0, #__json.data)
        end)
      end)
    end)
  end)
end
