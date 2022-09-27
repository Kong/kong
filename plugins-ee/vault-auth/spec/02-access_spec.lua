-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"
local parse_url = require("socket.url").parse


local VAULT_TOKEN = assert(os.getenv("VAULT_TOKEN"), "please set Vault Token in env var VAULT_TOKEN")
local VAULT_ADDR = assert(parse_url((assert(os.getenv("VAULT_ADDR"), "please set Vault URL in env var VAULT_ADDR"))))
local VAULT_MOUNT = assert(os.getenv("VAULT_MOUNT"), "please set Vault mount path in env var VAULT_MOUNT")
local VAULT_MOUNT_2 = assert(os.getenv("VAULT_MOUNT_2"), "please set Vault mount path in env var VAULT_MOUNT_2")

local PLUGIN_NAME = "vault-auth"

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local admin_client, proxy_client, consumer_1, cred_consumer_1,
          service_1, service_2
    local bp = helpers.get_db_utils(nil, nil, {"vault-auth"})

    lazy_setup(function()
      --[[ services and routes ]]
      service_1 = bp.services:insert {
        name = "test-service",
        url = "http://httpbin.org"
      }
      bp.routes:insert({
        hosts = { "test-1.com" },
        service = { id = service_1.id }
      })
      service_2 = bp.services:insert {
        name = "test-service-2",
        url = "http://httpbin.org"
      }
      bp.routes:insert({
        hosts = { "test-2.com" },
        service = { id = service_2.id }
      })

      --[[ consumer ]]
      consumer_1 = bp.consumers:insert({
        username = "consumer_1"
      })

      assert(helpers.start_kong( { plugins = "bundled,vault-auth" }))
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    describe("with multiple vaults", function()
      lazy_setup(function()
        local vault_1_id
        local mounts_services = {
          {
            VAULT_MOUNT,
            service_1
          },{
            VAULT_MOUNT_2,
            service_2
          }
        }

        for i, m_s in ipairs(mounts_services) do
          local vault_mount = m_s[1]
          local service = m_s[2]

          -- [[ vaults ]]
          local res_vault = assert(admin_client:send {
            method  = "POST",
            path    = "/vault-auth",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              host        = VAULT_ADDR.host,
              name        = "vault_" .. tostring(i),
              port        = tonumber(VAULT_ADDR.port),
              mount       = vault_mount,
              protocol    = VAULT_ADDR.scheme,
              vault_token = VAULT_TOKEN,
            }
          })
          local vault_json = assert.res_status(201, res_vault)
          local vault_body = cjson.decode(vault_json)
          local vault_id = vault_body.id
          if i == 1 then
            vault_1_id = vault_id
          end

          -- [[ plugins ]]
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/services/" .. service.id .. "/plugins",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              name = PLUGIN_NAME,
              config = {
                vault = { id = vault_id }
              }
            }
          })
          assert.res_status(201, res)
        end

        --[[ credentials ]]
        local res_cred = assert(admin_client:send {
          method  = "POST",
          path    = "/vault-auth/" .. vault_1_id .. "/credentials",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            consumer = { id = consumer_1.id }
          }
        })
        local cred_json = assert.res_status(201, res_cred)
        local cred_body = cjson.decode(cred_json)
        cred_consumer_1 = cred_body.data
      end)


      describe("denies access", function()
        it("when consumers who have valid cached credentials try to " ..
           "access another service/vault where they do not have access", function()
          local res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-1.com"
            },
            query = {
              access_token = cred_consumer_1.access_token,
              secret_token = cred_consumer_1.secret_token
            }
          })
          assert.res_status(200, res)

          res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-2.com"
            },
            query = {
              access_token = cred_consumer_1.access_token,
              secret_token = cred_consumer_1.secret_token
            }
          })
          assert.res_status(401, res)
        end)
      end)
    end)
  end)
end
