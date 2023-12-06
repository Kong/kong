-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson     = require "cjson"
local helpers   = require "spec.helpers"
local parse_url = require("socket.url").parse


local VAULT_TOKEN    = assert(os.getenv("VAULT_TOKEN"), "please set Vault Token in env var VAULT_TOKEN")
local VAULT_ADDR     = assert(parse_url((assert(os.getenv("VAULT_ADDR"), "please set Vault URL in env var VAULT_ADDR"))))
local VAULT_MOUNT    = assert(os.getenv("VAULT_MOUNT"), "please set Vault mount path in env var VAULT_MOUNT")
local VAULT_MOUNT_2  = assert(os.getenv("VAULT_MOUNT_2"), "please set Vault mount path in env var VAULT_MOUNT_2")
local VAULT_MOUNT_V2 = assert(os.getenv("VAULT_MOUNT_V2"), "please set Vault mount path in env var VAULT_MOUNT_V2")


local PLUGIN_NAME = "vault-auth"


local function vault_setup(admin_client, vault_items)
  for i, v in ipairs(vault_items) do
    local mount    = v.mount
    local kv       = v.kv
    local service  = v.service
    local consumer = v.consumer

    -- [[ vaults ]]
    local res = assert(admin_client:send {
      method  = "POST",
      path    = "/vault-auth",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        host        = VAULT_ADDR.host,
        port        = tonumber(VAULT_ADDR.port),
        mount       = mount,
        protocol    = VAULT_ADDR.scheme,
        vault_token = VAULT_TOKEN,
        kv          = kv
      }
    })
    local json              = assert.res_status(201, res)
    local body              = cjson.decode(json)
    local vault_id          = body.id
    vault_items[i].vault_id = vault_id

    -- [[ plugins ]]
    res = assert(admin_client:send {
      method  = "POST",
      path    = "/services/" .. service.id .. "/plugins",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        name    = PLUGIN_NAME,
        config  = {
          vault = { id = vault_id }
        }
      }
    })
    json = assert.res_status(201, res)
    body = cjson.decode(json)
    vault_items[i].plugin_id = body.id

    --[[ credentials ]]
    res = assert(admin_client:send {
      method  = "POST",
      path    = "/vault-auth/" .. vault_id .. "/credentials",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        consumer = { id = consumer.id }
      }
    })
    json = assert.res_status(201, res)
    body = cjson.decode(json)
    vault_items[i].cred_consumer = body.data
  end
end


local function vault_teardown(admin_client, vault_items)
  for _, v in ipairs(vault_items) do
    assert.res_status(204, assert(admin_client:send {
      method  = "DELETE",
      path    = "/services/" ..
                v.service.id ..
                "/plugins/"  ..
                v.plugin_id,
    }))

    assert.res_status(204, assert(admin_client:send {
      method  = "DELETE",
      path    = "/vault-auth/"               ..
                v.vault_id                   ..
                "/credentials/token/"        ..
                v.cred_consumer.access_token
    }))

    assert.res_status(204, assert(admin_client:send {
      method  = "DELETE",
      path    = "/vault-auth/" .. v.vault_id
    }))
  end
end


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local admin_client, proxy_client, consumer_1, consumer_2,
          service_1, service_2
    local bp = helpers.get_db_utils(nil, nil, {"vault-auth"})

    lazy_setup(function()
      --[[ services and routes ]]
      service_1 = bp.services:insert {
        name = "test-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }
      bp.routes:insert({
        hosts   = { "test-1.test" },
        service = { id = service_1.id }
      })
      service_2 = bp.services:insert {
        name = "test-service-2",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }
      bp.routes:insert({
        hosts   = { "test-2.test" },
        service = { id = service_2.id }
      })

      --[[ consumers ]]
      consumer_1 = bp.consumers:insert({
        username = "consumer_1"
      })
      consumer_2 = bp.consumers:insert({
        username = "consumer_2"
      })

      assert(helpers.start_kong( {
        plugins = "bundled,vault-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template"
      }))
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

    describe("with kv secrets engines v1 and v2", function()
      local vault_items = {}

      lazy_setup(function()
        vault_items = {
          {
            mount    = VAULT_MOUNT,
            kv       = "v1",
            service  = service_1,
            consumer = consumer_1
          },{
            mount    = VAULT_MOUNT_V2,
            kv       = "v2",
            service  = service_2,
            consumer = consumer_2
          }
        }
        vault_setup(admin_client, vault_items)
      end)

      lazy_teardown(function()
        vault_teardown(admin_client, vault_items)
      end)

      it("allows access when credentials are correct", function()
        for i, v in ipairs(vault_items) do
          local res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-" .. i .. ".test"
            },
            query = {
              access_token = v.cred_consumer.access_token,
              secret_token = v.cred_consumer.secret_token
            }
          })
          assert.res_status(200, res)
        end
      end)

      it("denies access when credentials are incorrect", function()
        for i = 1, #vault_items do
          local wrong_consumer_creds = vault_items[#vault_items - i + 1]
                                       .cred_consumer
          local res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-" .. i .. ".test"
            },
            query = {
              access_token = wrong_consumer_creds.access_token,
              secret_token = wrong_consumer_creds.secret_token
            }
          })
          assert.res_status(401, res)
        end
      end)

      it("denies access when valid credentials are deleted", function()
        for i, v in ipairs(vault_items) do
          assert.res_status(200, assert(proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-" .. i .. ".test"
            },
            query = {
              access_token = v.cred_consumer.access_token,
              secret_token = v.cred_consumer.secret_token
            }
          })))

          assert.res_status(204, assert(admin_client:send {
            method  = "DELETE",
            path    = "/vault-auth/"               ..
                      v.vault_id                   ..
                      "/credentials/token/"        ..
                      v.cred_consumer.access_token
          }))

          assert.res_status(401, assert(proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-" .. i .. ".test"
            },
            query = {
              access_token = v.cred_consumer.access_token,
              secret_token = v.cred_consumer.secret_token
            }
          })))
        end
      end)
    end)

    describe("with multiple vaults", function()
      local vault_items = {}

      lazy_setup(function()
        vault_items = {
          {
            mount    = VAULT_MOUNT,
            kv       = "v1",
            service  = service_1,
            consumer = consumer_1
          },{
            mount    = VAULT_MOUNT_2,
            kv       = "v1",
            service  = service_2,
            consumer = consumer_2
          }
        }
        vault_setup(admin_client, vault_items)
      end)

      lazy_teardown(function()
        vault_teardown(admin_client, vault_items)
      end)

      describe("denies access", function()
        it("when consumers who have valid cached credentials try to " ..
           "access another service/vault where they do not have access", function()
          local cred_consumer = vault_items[1].cred_consumer
          local res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-1.test"
            },
            query = {
              access_token = cred_consumer.access_token,
              secret_token = cred_consumer.secret_token
            }
          })
          assert.res_status(200, res)

          res = proxy_client:get("/get", {
            headers = {
              ["Host"] = "test-2.test"
            },
            query = {
              access_token = cred_consumer.access_token,
              secret_token = cred_consumer.secret_token
            }
          })
          assert.res_status(401, res)
        end)
      end)
    end)
  end)
end
