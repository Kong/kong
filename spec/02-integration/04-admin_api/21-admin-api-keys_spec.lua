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

for _, strategy in helpers.all_strategies() do
  describe("Admin API - keys #" .. strategy, function()
    local pem_pub, pem_priv, jwk
    helpers.setenv("SECRET_JWK", '{"alg": "RSA-OAEP", "kid": "test"}')
    local client
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "keys",
        "key_sets"})

      local jwk_pub, jwk_priv = helpers.generate_keys("JWK")
      pem_pub, pem_priv = helpers.generate_keys("PEM")

      jwk = merge(cjson.decode(jwk_pub), cjson.decode(jwk_priv))

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled"
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

    describe("/keys and /key-sets", function()
      local test_jwk_key, test_pem_key
      local test_key_set
      lazy_setup(function()
        local r_key_set = helpers.admin_client():post("/key-sets", {
          headers = HEADERS,
          body = {
            name = "test",
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

      describe("POST", function()
        it(":insert keys, without setting the field `set`", function()
          local p_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "unique pem key1",
              jwk = cjson.encode(jwk),
              kid = jwk.kid
            }
          })
          assert.res_status(201, p_key)
        end)

        it(":insert keys, with the valid jwk field", function()
          local j_without_set_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "unique jwk2 key without set",
              jwk = "{\"kid\":\"34\"}",
              kid = "34"
            }
          })
          assert.res_status(201, j_without_set_key)
        end)

        it(":insert keys, should be throw an error when the field `jwk` not valid JSON.", function()
          local j_without_set_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "unique jwk3 key",
              jwk = "\"kid\":test",
              kid = "35"
            }
          })
          local p_key_body = assert.res_status(400, j_without_set_key)
          local body = cjson.decode(p_key_body)
          assert.same(body.message, "schema violation (could not json decode jwk string)")
        end)

        it(":insert keys, should be throw an error when the `keys.kid` is not equal to `jwk kid`.", function()
          local p_key = helpers.admin_client():post("/keys", {
            headers = HEADERS,
            body = {
              name = "unique pem key4",
              jwk = cjson.encode(jwk),
              kid = "test_pem"
            }
          })
          local p_key_body = assert.res_status(400, p_key)
          local body = cjson.decode(p_key_body)
          assert.same(body.message, "schema violation (kid in jwk.kid must be equal to keys.kid)")
        end)
      end)

      describe("GET", function()
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

      describe("PATCH", function()
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

      describe("DELETE", function()
        it("cascade deletes keys when key-set is deleted", function()
          -- assert we have 1 key-sets
          local res = client:get("/key-sets")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.data)
          -- assert we have 1 key
          local res_ = client:get("/keys")
          local body_ = assert.res_status(200, res_)
          local json_ = cjson.decode(body_)
          assert.equal(4, #json_.data)

          local d_res = client:delete("/key-sets/"..json.data[1].id)
          assert.res_status(204, d_res)

          -- assert keys were deleted (by cascade)
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
