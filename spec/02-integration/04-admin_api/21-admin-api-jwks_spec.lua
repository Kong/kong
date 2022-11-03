-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"


local HEADERS = { ["Content-Type"] = "application/json" }

for _, strategy in helpers.each_strategy() do
  describe("Admin API - jwks #" .. strategy, function()
    helpers.setenv("SECRET_JWK", '{"alg": "RSA-OAEP", "kid": "test"}')
    local client
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "jwks",
        "jwk_sets"})

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

    describe("/jwks", function()
      local test_jwk
      local test_jwk_set
      lazy_setup(function()
        local r_jwk_set = helpers.admin_client():post("/jwk-sets", {
          headers = HEADERS,
          body = {
            name = "test",
          },
        })
        local body = assert.res_status(201, r_jwk_set)
        local jwk_set = cjson.decode(body)
        test_jwk_set = jwk_set

        local r_jwk = helpers.admin_client():post("/jwks", {
          headers = HEADERS,
          body = {
            name = "unique jwk name",
            set = { id = jwk_set.id },
            jwk = { kid = "testkid" },
            kid = "testkid"
          }
        })
        local jwk_body = assert.res_status(201, r_jwk)
        local jwk = cjson.decode(jwk_body)
        test_jwk = jwk
      end)

      describe("GET", function()
        it("retrieves all jwk-sets and jwks configured", function()
          local res = client:get("/jwk-sets")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.data)
          local _res = client:get("/jwks")
          local _body = assert.res_status(200, _res)
          local _json = cjson.decode(_body)
          assert.equal(1, #_json.data)
        end)
      end)

      describe("PATCH", function()
        it("updates a jwk-set by id", function()
          local res = client:patch("/jwk-sets/" .. test_jwk_set.id, {
            headers = HEADERS,
            body = {
              name = "changeme"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("changeme", json.name)
        end)

        it("updates a jwk by id", function()
          local res = client:patch("/jwks/" .. test_jwk.id, {
            headers = HEADERS,
            body = {
              name = "changeme"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("changeme", json.name)
        end)
      end)

      describe("DELETE", function()
        it("cascade deletes jwks when jwk-set is deleted", function()
          -- assert we have 1 jwk-sets
          local res = client:get("/jwk-sets")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #json.data)
          -- assert we have 1 jwk
          local res_ = client:get("/jwks")
          local body_ = assert.res_status(200, res_)
          local json_ = cjson.decode(body_)
          assert.equal(1, #json_.data)

          local d_res = client:delete("/jwk-sets/"..json.data[1].id)
          assert.res_status(204, d_res)

          -- assert jwks were deleted (by cascade)
          local _res = client:get("/jwks")
          local _body = assert.res_status(200, _res)
          local _json = cjson.decode(_body)
          assert.equal(0, #_json.data)

          -- assert jwk-sets were deleted
          local __res = client:get("/jwk-sets")
          local __body = assert.res_status(200, __res)
          local __json = cjson.decode(__body)
          assert.equal(0, #__json.data)
        end)
      end)
    end)
  end)
end
