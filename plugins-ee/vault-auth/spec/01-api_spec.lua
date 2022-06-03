-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid
local parse_url = require("socket.url").parse


local VAULT_TOKEN = assert(os.getenv("VAULT_TOKEN"), "please set Vault Token in env var VAULT_TOKEN")
local VAULT_ADDR = assert(parse_url((assert(os.getenv("VAULT_ADDR"), "please set Vault URL in env var VAULT_ADDR"))))
local VAULT_MOUNT = assert(os.getenv("VAULT_MOUNT"), "please set Vault mount path in env var VAULT_MOUNT")


describe("Plugin: vault (API)",function()
  local admin_client, vault_id, consumer_id, cred


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
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/vault-auth",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            host        = VAULT_ADDR.host,
            port        = tonumber(VAULT_ADDR.port),
            mount       = VAULT_MOUNT,
            protocol    = VAULT_ADDR.scheme,
            vault_token = VAULT_TOKEN,
          }
        })

        local json = assert.res_status(201, res)
        local body = cjson.decode(json)
        vault_id = body.id

        res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            username = "bob",
          }
        })

        json = assert.res_status(201, res)
        body = cjson.decode(json)
        consumer_id = body.id
      end)



      describe("POST", function()

        it("creates a new Vault credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth/" .. vault_id .. "/credentials",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              consumer = { id = consumer_id }
            }
          })

          local json = assert.res_status(201, res)
          local body = cjson.decode(json)
          cred = body.data

          assert(cred.access_token)
          assert(cred.secret_token)
          assert.same(consumer_id, cred.consumer.id)
          assert.is_same(ngx.null, cred.ttl)
        end)

      end)

      describe("GET", function()

        it("returns an existing Vault credential", function()
          local res = assert(admin_client:send {
            method = "GET",
            path   = "/vault-auth/" .. vault_id .. "/credentials",
          })

          local json = assert.res_status(200, res)
          local body = cjson.decode(json)

          assert.same(cred, body.data[1])
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

      end)

    end)



    describe("/vault-auth/:vault/credentials/:consumer", function()

      describe("POST", function()

        it("creates a new Vault credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth/" .. vault_id .. "/credentials/" .. consumer_id,
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {},
          })

          assert.res_status(201, res)
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
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth/" .. vault_id .. "/credentials/" .. uuid(),
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {},
          })

          assert.res_status(404, res)
        end)

      end)

    end)



    describe("/vault-auth/:vault/credentials/token/:access_token", function()

      describe("GET", function()

        it("returns a credential", function()
          local res = assert(admin_client:send {
            method = "GET",
            path   = "/vault-auth/" .. vault_id .. "/credentials/token/" .. cred.access_token,
          })

          local json = assert.res_status(200, res)
          local body = cjson.decode(json)
          assert.same(cred, body.data)
        end)
      end)



      describe("DELETE", function()
        it("deletes a credential", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path   = "/vault-auth/" .. vault_id .. "/credentials/token/" .. cred.access_token,
          })

          assert.res_status(204, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/vault-auth/" .. vault_id .. "/credentials/token/" .. cred.access_token,
          })

          assert.res_status(404, res)
        end)

      end)

    end)

  end)

end)
