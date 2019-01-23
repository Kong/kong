local cjson   = require "cjson"
local helpers = require "spec.helpers"

local uuid = require("kong.tools.utils").uuid

local function capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

local VAULT_TOKEN

describe("Plugin: vault (API)",function()
  local admin_client, vault_id, consumer_id, cred

  describe("Vault instances", function()
    setup(function()
      local out = capture("vault token create")
      local m = ngx.re.match(out, [[token\s+([\w.]+)]])

      VAULT_TOKEN= m[1]

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

    describe("/vaults/:vault/credentials", function()
      setup(function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/vaults",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            host        = "127.0.0.1",
            mount       = "kong-auth",
            protocol    = "http",
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
            path    = "/vaults/" .. vault_id .. "/credentials",
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
            path   = "/vaults/" .. vault_id .. "/credentials",
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
            path    = "/vaults/" .. uuid() .. "/credentials",
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
            path    = "/vaults/" .. vault_id .. "/credentials",
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
            path    = "/vaults/" .. vault_id .. "/credentials",
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

    describe("/vaults/:vault/credentials/:consumer", function()
      describe("POST", function()
        it("creates a new Vault credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/vaults/" .. vault_id .. "/credentials/" .. consumer_id,
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
            path    = "/vaults/" .. uuid() .. "/credentials/" .. consumer_id,
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
            path    = "/vaults/" .. vault_id .. "/credentials/" .. uuid(),
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {},
          })

          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/vaults/:vault/credentials/token/:access_token", function()
      describe("GET", function()
        it("returns a credential", function()
          local res = assert(admin_client:send {
            method = "GET",
            path   = "/vaults/" .. vault_id .. "/credentials/token/" .. cred.access_token,
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
            path   = "/vaults/" .. vault_id .. "/credentials/token/" .. cred.access_token,
          })
          
          assert.res_status(204, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/vaults/" .. vault_id .. "/credentials/token/" .. cred.access_token,
          })
          
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)
