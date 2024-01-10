-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid
local compare_no_order = require "pl.tablex".compare_no_order


local VAULT_TOKEN = "vault-plaintext-root-token"
local VAULT_HOST = os.getenv("KONG_SPEC_TEST_VAULT_HOST") or "vault"
local VAULT_PORT = tonumber(os.getenv("KONG_SPEC_TEST_VAULT_PORT_8200")) or 8200
local VAULT_MOUNT = "kong-auth"
local VAULT_MOUNT_V2 = "kong-auth-v2"


describe("Plugin: vault (API)",function()
  local vault_items = {
    {
      mount = VAULT_MOUNT,
      kv    = "v1"
    },{
      mount = VAULT_MOUNT_V2,
      kv    = "v2"
    }
  }
  local admin_client, consumer_id


  describe("Vault instances", function()

    setup(function()
      helpers.get_db_utils(nil, nil, {"vault-auth"})
      assert(helpers.start_kong({
        plugins = "bundled,vault-auth",
      }))

      admin_client = helpers.admin_client()
    end)


    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)



    describe("/vault-auth/:vault/credentials", function()

      setup(function()
        for i, v in ipairs(vault_items) do
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              host        = VAULT_HOST,
              port        = VAULT_PORT,
              mount       = v.mount,
              protocol    = "http",
              vault_token = VAULT_TOKEN,
              kv          = v.kv
            }
          })

          local json = assert.res_status(201, res)
          local body = cjson.decode(json)
          vault_items[i].vault_id = body.id
        end

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            username = "bob",
          }
        })

        local json = assert.res_status(201, res)
        local body = cjson.decode(json)
        consumer_id = body.id
      end)



      describe("POST", function()

        it("creates a new Vault credential", function()
          for i, v in ipairs(vault_items) do
            local path = "/vault-auth/" .. v.vault_id .. "/credentials"
            local res = assert(admin_client:send {
              method  = "POST",
              path    = path,
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {
                consumer = { id = consumer_id }
              }
            })

            local json = assert.res_status(201, res)
            local body = cjson.decode(json)
            local cred = body.data

            assert(cred.access_token)
            assert(cred.secret_token)
            assert.same(consumer_id, cred.consumer.id)
            assert.is_same(ngx.null, cred.ttl)
            vault_items[i].cred = cred
          end
        end)

      end)

      describe("GET", function()

        it("returns an existing Vault credential", function()
          for _, v in ipairs(vault_items) do
            local res = assert(admin_client:send {
              method = "GET",
              path   = "/vault-auth/" .. v.vault_id .. "/credentials",
            })
            local json = assert.res_status(200, res)
            local body = cjson.decode(json)
            local found = false
            for _, credential in ipairs(body.data) do
              if compare_no_order(v.cred, credential) then
                found = true
              end
            end
            assert.is_true(found)
          end
        end)
      end)



      describe("errors", function()
        it("with a 404 when the given Vault doesn't exist", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth/" .. uuid() .. "/credentials",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              consumer = { id = consumer_id }
            }
          })

          assert.res_status(404, res)
        end)
        for _, v in ipairs(vault_items) do
          local vault_id = v.vault_id

          it("with a 400 when a Consumer is not passed", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/vault-auth/" .. vault_id .. "/credentials",
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {},
            })

            assert.res_status(400, res)
          end)


          it("with a 404 when the given Consumer does not exist", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/vault-auth/" .. vault_id .. "/credentials",
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {
                consumer = { id = uuid() }
              },
            })

            assert.res_status(404, res)
          end)
        end

      end)

    end)



    describe("/vault-auth/:vault/credentials/:consumer", function()

      describe("POST", function()
        it("creates a new Vault credential", function()
          for _, v in ipairs(vault_items) do
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/vault-auth/" .. v.vault_id .. "/credentials/" .. consumer_id,
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {},
            })

            assert.res_status(201, res)
          end
        end)

      end)



      describe("errors", function()

        it("with a 404 when the given Vault doesn't exist", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth/" .. uuid() .. "/credentials/" .. consumer_id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {},
          })

          assert.res_status(404, res)
        end)


        it("with a 404 when the given Consumer does not exist", function()
          for _, v in ipairs(vault_items) do
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/vault-auth/" .. v.vault_id .. "/credentials/" .. uuid(),
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {},
            })

            assert.res_status(404, res)
          end
        end)

      end)

    end)



    describe("/vault-auth/:vault/credentials/token/:access_token", function()

      describe("GET", function()

        it("returns a credential", function()
          for _, v in ipairs(vault_items) do
            local res = assert(admin_client:send {
              method = "GET",
              path   = "/vault-auth/" .. v.vault_id .. "/credentials/token/" .. v.cred.access_token,
            })

            local json = assert.res_status(200, res)
            local body = cjson.decode(json)
            assert.same(v.cred, body.data)
          end
        end)
      end)



      describe("DELETE", function()
        it("deletes a credential", function()
          for _, v in ipairs(vault_items) do
            local res = assert(admin_client:send {
              method = "DELETE",
              path   = "/vault-auth/" .. v.vault_id .. "/credentials/token/" .. v.cred.access_token,
            })

            assert.res_status(204, res)

            res = assert(admin_client:send {
              method = "GET",
              path   = "/vault-auth/" .. v.vault_id .. "/credentials/token/" .. v.cred.access_token,
            })

            assert.res_status(404, res)
          end
        end)

      end)

    end)

  end)

end)
