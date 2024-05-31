local helpers = require "spec.helpers"
local cjson = require "cjson"
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local uuid = require("kong.tools.uuid").uuid

local admin = require "spec.fixtures.admin_api"

local CP_HOST = "127.0.0.1"
local CP_PORT = 9005

local PLUGIN_LIST


local function cluster_client(opts)
  opts = opts or {}
  local res, err = helpers.clustering_client({
    host = CP_HOST,
    port = CP_PORT,
    cert = "spec/fixtures/kong_clustering.crt",
    cert_key = "spec/fixtures/kong_clustering.key",
    node_hostname = opts.hostname or "test",
    node_id = opts.id or uuid(),
    node_version = opts.version,
    node_plugins_list = PLUGIN_LIST,
  })

  assert.is_nil(err)
  if res and res.config_table then
    res.config = res.config_table
  end

  return res
end

local function get_plugin(node_id, node_version, name)
  local res, err = cluster_client({ id = node_id, version = node_version })
  assert.is_nil(err)
  assert.is_table(res and res.config_table and res.config_table.plugins,
                  "invalid response from clustering client")

  local plugin
  for _, p in ipairs(res.config_table.plugins or {}) do
    if p.name == name then
      plugin = p
      break
    end
  end

  assert.not_nil(plugin, "plugin " .. name .. " not found in config")
  return plugin
end


local function get_sync_status(id)
  local status
  local admin_client = helpers.admin_client()

  helpers.wait_until(function()
    local res = admin_client:get("/clustering/data-planes")
    local body = assert.res_status(200, res)

    local json = cjson.decode(body)

    for _, v in pairs(json.data) do
      if v.id == id then
        status = v.sync_status
        return true
      end
    end
  end, 5, 0.5)

  admin_client:close()

  return status
end


for _, strategy in helpers.each_strategy() do

describe("CP/DP config compat transformations #" .. strategy, function()
  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy)

    PLUGIN_LIST = helpers.get_plugins_list()

    bp.routes:insert {
      name = "compat.test",
      hosts = { "compat.test" },
      service = bp.services:insert {
        name = "compat.test",
      }
    }

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      database = strategy,
      db_update_frequency = 0.1,
      cluster_listen = CP_HOST .. ":" .. CP_PORT,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("plugin config fields", function()
    local function do_assert(node_id, node_version, expected_entity)
      local plugin = get_plugin(node_id, node_version, expected_entity.name)
      assert.same(expected_entity.config, plugin.config)
      assert.equals(CLUSTERING_SYNC_STATUS.NORMAL, get_sync_status(node_id))
    end

    it("removes new fields before sending them to older DP nodes", function()
      local rate_limit = admin.plugins:insert {
        name = "rate-limiting",
        enabled = true,
        config = {
          second = 1,
          policy = "redis",
          redis = {
            host = "localhost"
          },

          -- [[ new fields
          error_code = 403,
          error_message = "go away!",
          sync_rate = -1,
          -- ]]
        },
      }
      --[[
        For 3.0.x
        should not have: error_code, error_message, sync_rate
      --]]
      local expected = cycle_aware_deep_copy(rate_limit)
      expected.config.redis = nil
      expected.config.error_code = nil
      expected.config.error_message = nil
      expected.config.sync_rate = nil
      do_assert(uuid(), "3.0.0", expected)


      --[[
        For 3.2.x
        should have: error_code, error_message
        should not have: sync_rate
      --]]
      expected = cycle_aware_deep_copy(rate_limit)
      expected.config.redis = nil
      expected.config.sync_rate = nil
      do_assert(uuid(), "3.2.0", expected)


      --[[
        For 3.3.x,
        should have: error_code, error_message
        should not have: sync_rate
      --]]
      expected = cycle_aware_deep_copy(rate_limit)
      expected.config.redis = nil
      expected.config.sync_rate = nil
      do_assert(uuid(), "3.3.0", expected)

      -- cleanup
      admin.plugins:remove({ id = rate_limit.id })
    end)

    it("does not remove fields from DP nodes that are already compatible", function()
      local rate_limit = admin.plugins:insert {
        name = "rate-limiting",
        enabled = true,
        config = {
          second = 1,
          policy = "redis",
          redis = {
            host = "localhost"
          },

          -- [[ new fields
          error_code = 403,
          error_message = "go away!",
          sync_rate = -1,
          -- ]]
        },
      }

      local expected = cycle_aware_deep_copy(rate_limit)
      expected.config.redis = nil
      do_assert(uuid(), "3.4.0", expected)

      -- cleanup
      admin.plugins:remove({ id = rate_limit.id })
    end)

    describe("compatibility test for cors plugin", function()
      it("removes `config.private_network` before sending them to older(less than 3.5.0.0) DP nodes", function()
        local cors = admin.plugins:insert {
          name = "cors",
          enabled = true,
          config = {
            -- [[ new fields 3.5.0
            private_network = false
            -- ]]
          }
        }

        assert.not_nil(cors.config.private_network)
        local expected_cors = cycle_aware_deep_copy(cors)
        expected_cors.config.private_network = nil
        do_assert(uuid(), "3.4.0", expected_cors)

        -- cleanup
        admin.plugins:remove({ id = cors.id })
      end)

      it("does not remove `config.private_network` from DP nodes that are already compatible", function()
        local cors = admin.plugins:insert {
          name = "cors",
          enabled = true,
          config = {
            -- [[ new fields 3.5.0
            private_network = false
            -- ]]
          }
        }
        do_assert(uuid(), "3.5.0", cors)

        -- cleanup
        admin.plugins:remove({ id = cors.id })
      end)
    end)

    describe("compatibility tests for opentelemetry plugin", function()
      it("replaces `aws` values of `header_type` property with default `preserve`", function()
        -- [[ 3.5.x ]] --
        local opentelemetry = admin.plugins:insert {
          name = "opentelemetry",
          enabled = true,
          config = {
            endpoint = "http://1.1.1.1:12345/v1/trace",
            -- [[ new value 3.5.0
            header_type = "gcp"
            -- ]]
          }
        }

        local expected_otel_prior_35 = cycle_aware_deep_copy(opentelemetry)
        expected_otel_prior_35.config.header_type = "preserve"
        expected_otel_prior_35.config.sampling_rate = nil
        expected_otel_prior_35.config.propagation = nil
        do_assert(uuid(), "3.4.0", expected_otel_prior_35)

        -- cleanup
        admin.plugins:remove({ id = opentelemetry.id })

        -- [[ 3.4.x ]] --
        opentelemetry = admin.plugins:insert {
          name = "opentelemetry",
          enabled = true,
          config = {
            endpoint = "http://1.1.1.1:12345/v1/trace",
            -- [[ new value 3.4.0
            header_type = "aws"
            -- ]]
          }
        }

        local expected_otel_prior_34 = cycle_aware_deep_copy(opentelemetry)
        expected_otel_prior_34.config.header_type = "preserve"
        expected_otel_prior_34.config.sampling_rate = nil
        expected_otel_prior_34.config.propagation = nil
        do_assert(uuid(), "3.3.0", expected_otel_prior_34)

        -- cleanup
        admin.plugins:remove({ id = opentelemetry.id })
      end)

    end)

    describe("compatibility tests for zipkin plugin", function()
      it("replaces `aws` and `gcp` values of `header_type` property with default `preserve`", function()
        -- [[ 3.5.x ]] --
        local zipkin = admin.plugins:insert {
          name = "zipkin",
          enabled = true,
          config = {
            http_endpoint = "http://1.1.1.1:12345/v1/trace",
            -- [[ new value 3.5.0
            header_type = "gcp"
            -- ]]
          }
        }

        local expected_zipkin_prior_35 = cycle_aware_deep_copy(zipkin)
        expected_zipkin_prior_35.config.header_type = "preserve"
        expected_zipkin_prior_35.config.default_header_type = "b3"
        expected_zipkin_prior_35.config.propagation = nil
        do_assert(uuid(), "3.4.0", expected_zipkin_prior_35)

        -- cleanup
        admin.plugins:remove({ id = zipkin.id })

        -- [[ 3.4.x ]] --
        zipkin = admin.plugins:insert {
          name = "zipkin",
          enabled = true,
          config = {
            http_endpoint = "http://1.1.1.1:12345/v1/trace",
            -- [[ new value 3.4.0
            header_type = "aws"
            -- ]]
          }
        }

        local expected_zipkin_prior_34 = cycle_aware_deep_copy(zipkin)
        expected_zipkin_prior_34.config.header_type = "preserve"
        expected_zipkin_prior_34.config.default_header_type = "b3"
        expected_zipkin_prior_34.config.propagation = nil
        do_assert(uuid(), "3.3.0", expected_zipkin_prior_34)

        -- cleanup
        admin.plugins:remove({ id = zipkin.id })
      end)
    end)

    describe("compatibility tests for redis standarization", function()
      describe("acme plugin", function()
        it("translates standardized redis config to older acme structure", function()
          -- [[ 3.6.x ]] --
          local acme = admin.plugins:insert {
            name = "acme",
            enabled = true,
            config = {
              account_email = "test@example.com",
              storage = "redis",
              storage_config = {
                -- [[ new structure redis
                redis = {
                  host = "localhost",
                  port = 57198,
                  username = "test",
                  password = "secret",
                  database = 2,
                  timeout = 1100,
                  ssl = true,
                  ssl_verify = true,
                  server_name = "example.test",
                  extra_options = {
                    namespace = "test_namespace",
                    scan_count = 13
                  }
                }
                -- ]]
              }
            }
          }

          local expected_acme_prior_36 = cycle_aware_deep_copy(acme)
          expected_acme_prior_36.config.storage_config.redis = {
            host = "localhost",
            port = 57198,
            auth = "secret",
            database = 2,
            ssl = true,
            ssl_verify = true,
            ssl_server_name = "example.test",
            namespace = "test_namespace",
            scan_count = 13
          }
          do_assert(uuid(), "3.5.0", expected_acme_prior_36)

          -- cleanup
          admin.plugins:remove({ id = acme.id })
        end)
      end)

      describe("rate-limiting plugin", function()
        it("translates standardized redis config to older rate-limiting structure", function()
          -- [[ 3.6.x ]] --
          local rl = admin.plugins:insert {
            name = "rate-limiting",
            enabled = true,
            config = {
              minute = 300,
              policy = "redis",
              -- [[ new structure redis
              redis = {
                  host = "localhost",
                  port = 57198,
                  username = "test",
                  password = "secret",
                  database = 2,
                  timeout = 1100,
                  ssl = true,
                  ssl_verify = true,
                  server_name = "example.test"
              }
              -- ]]
            }
          }

          local expected_rl_prior_36 = cycle_aware_deep_copy(rl)
          expected_rl_prior_36.config.redis = nil
          expected_rl_prior_36.config.redis_host = "localhost"
          expected_rl_prior_36.config.redis_port = 57198
          expected_rl_prior_36.config.redis_username = "test"
          expected_rl_prior_36.config.redis_password = "secret"
          expected_rl_prior_36.config.redis_database = 2
          expected_rl_prior_36.config.redis_timeout = 1100
          expected_rl_prior_36.config.redis_ssl = true
          expected_rl_prior_36.config.redis_ssl_verify = true
          expected_rl_prior_36.config.redis_server_name = "example.test"


          do_assert(uuid(), "3.5.0", expected_rl_prior_36)

          -- cleanup
          admin.plugins:remove({ id = rl.id })
        end)
      end)

      describe("response-ratelimiting plugin", function()
        it("translates standardized redis config to older response-ratelimiting structure", function()
          -- [[ 3.6.x ]] --
          local response_rl = admin.plugins:insert {
            name = "response-ratelimiting",
            enabled = true,
            config = {
              limits = {
                video = {
                  minute = 300,
                }
              },
              policy = "redis",
              -- [[ new structure redis
              redis = {
                host = "localhost",
                port = 57198,
                username = "test",
                password = "secret",
                database = 2,
                timeout = 1100,
                ssl = true,
                ssl_verify = true,
                server_name = "example.test"
              }
              -- ]]
            }
          }

          local expected_response_rl_prior_36 = cycle_aware_deep_copy(response_rl)
          expected_response_rl_prior_36.config.redis = nil
          expected_response_rl_prior_36.config.redis_host = "localhost"
          expected_response_rl_prior_36.config.redis_port = 57198
          expected_response_rl_prior_36.config.redis_username = "test"
          expected_response_rl_prior_36.config.redis_password = "secret"
          expected_response_rl_prior_36.config.redis_database = 2
          expected_response_rl_prior_36.config.redis_timeout = 1100
          expected_response_rl_prior_36.config.redis_ssl = true
          expected_response_rl_prior_36.config.redis_ssl_verify = true
          expected_response_rl_prior_36.config.redis_server_name = "example.test"


          do_assert(uuid(), "3.5.0", expected_response_rl_prior_36)

          -- cleanup
          admin.plugins:remove({ id = response_rl.id })
        end)
      end)

      describe("proxy-cache plugin", function()
        it("rename age field in response_headers config from age to Age", function()
          -- [[ 3.8.x ]] --
          local response_rl = admin.plugins:insert {
            name = "proxy-cache",
            enabled = true,
            config = {
              response_code = { 200, 301, 404 },
              request_method = { "GET", "HEAD" },
              content_type = { "text/plain", "application/json" },
              cache_ttl = 300,
              strategy = "memory",
              cache_control = false,
              memory = {
                dictionary_name = "kong_db_cache",
              },
              -- [[ age field renamed to Age
              response_headers = {
                ["Age"] = true,
                ["X-Cache-Status"] = true,
                ["X-Cache-Key"] = true
              }
              -- ]]
            }
          }

          local expected_response_rl_prior_38 = cycle_aware_deep_copy(response_rl)
          expected_response_rl_prior_38.config.response_headers = {
            ["age"] = true,
            ["X-Cache-Status"] = true,
            ["X-Cache-Key"] = true
          }

          do_assert(uuid(), "3.7.0", expected_response_rl_prior_38)

          -- cleanup
          admin.plugins:remove({ id = response_rl.id })
        end)
      end)
    end)

    describe("ai plugins", function()
      it("[ai-proxy] sets unsupported AI LLM properties to nil or defaults", function()
        -- [[ 3.7.x ]] --
        local ai_proxy = admin.plugins:insert {
          name = "ai-proxy",
          enabled = true,
          config = {
            response_streaming = "allow", -- becomes nil
            route_type = "preserve", -- becomes 'llm/v1/chat'
            auth = {
              header_name = "header",
              header_value = "value",
            },
            model = {
              name = "any-model-name",
              provider = "openai",
              options = {
                max_tokens = 512,
                temperature = 0.5,
                upstream_path = "/anywhere", -- becomes nil
              },
            },
          },
        }
        -- ]]

        local expected_ai_proxy_prior_37 = cycle_aware_deep_copy(ai_proxy)
        expected_ai_proxy_prior_37.config.response_streaming = nil
        expected_ai_proxy_prior_37.config.model.options.upstream_path = nil
        expected_ai_proxy_prior_37.config.route_type = "llm/v1/chat"

        do_assert(uuid(), "3.6.0", expected_ai_proxy_prior_37)

        -- cleanup
        admin.plugins:remove({ id = ai_proxy.id })
      end)

      it("[ai-request-transformer] sets unsupported AI LLM properties to nil or defaults", function()
        -- [[ 3.7.x ]] --
        local ai_request_transformer = admin.plugins:insert {
          name = "ai-request-transformer",
          enabled = true,
          config = {
            prompt = "Convert my message to XML.",
            llm = {
              route_type = "llm/v1/chat",
              auth = {
                header_name = "header",
                header_value = "value",
              },
              model = {
                name = "any-model-name",
                provider = "azure",
                options = {
                  azure_instance = "azure-1",
                  azure_deployment_id = "azdep-1",
                  azure_api_version = "2023-01-01",
                  max_tokens = 512,
                  temperature = 0.5,
                  upstream_path = "/anywhere", -- becomes nil
                },
              },
            },
          },
        }
        -- ]]

        local expected_ai_request_transformer_prior_37 = cycle_aware_deep_copy(ai_request_transformer)
        expected_ai_request_transformer_prior_37.config.llm.model.options.upstream_path = nil

        do_assert(uuid(), "3.6.0", expected_ai_request_transformer_prior_37)

        -- cleanup
        admin.plugins:remove({ id = ai_request_transformer.id })
      end)

      it("[ai-response-transformer] sets unsupported AI LLM properties to nil or defaults", function()
        -- [[ 3.7.x ]] --
        local ai_response_transformer = admin.plugins:insert {
          name = "ai-response-transformer",
          enabled = true,
          config = {
            prompt = "Convert my message to XML.",
            llm = {
              route_type = "llm/v1/chat",
              auth = {
                header_name = "header",
                header_value = "value",
              },
              model = {
                name = "any-model-name",
                provider = "cohere",
                options = {
                  azure_api_version = "2023-01-01",
                  max_tokens = 512,
                  temperature = 0.5,
                  upstream_path = "/anywhere", -- becomes nil
                },
              },
            },
          },
        }
        -- ]]

        local expected_ai_response_transformer_prior_37 = cycle_aware_deep_copy(ai_response_transformer)
        expected_ai_response_transformer_prior_37.config.llm.model.options.upstream_path = nil

        do_assert(uuid(), "3.6.0", expected_ai_response_transformer_prior_37)

        -- cleanup
        admin.plugins:remove({ id = ai_response_transformer.id })
      end)
    end)

    describe("www-authenticate header in plugins (realm config)", function()
      it("[basic-auth] removes realm for versions below 3.6", function()
        local basic_auth = admin.plugins:insert {
          name = "basic-auth",
        }

        local expected_basic_auth_prior_36 = cycle_aware_deep_copy(basic_auth)
        expected_basic_auth_prior_36.config.realm = nil

        do_assert(uuid(), "3.5.0", expected_basic_auth_prior_36)

        -- cleanup
        admin.plugins:remove({ id = basic_auth.id })
      end)

      it("[key-auth] removes realm for versions below 3.7", function()
        local key_auth = admin.plugins:insert {
          name = "key-auth",
          config = {
            realm = "test"
          }
        }

        local expected_key_auth_prior_37 = cycle_aware_deep_copy(key_auth)
        expected_key_auth_prior_37.config.realm = nil

        do_assert(uuid(), "3.6.0", expected_key_auth_prior_37)

        -- cleanup
        admin.plugins:remove({ id = key_auth.id })
      end)
    end)

    describe("compatibility test for response-transformer plugin", function()
      it("removes `config.rename.json` before sending them to older(less than 3.8.0.0) DP nodes", function()
        local rt = admin.plugins:insert {
          name = "response-transformer",
          enabled = true,
          config = {
            rename = {
              -- [[ new fields 3.8.0
              json = {"old:new"}
              -- ]]
            }
          }
        }

        assert.not_nil(rt.config.rename.json)
        local expected_rt = cycle_aware_deep_copy(rt)
        expected_rt.config.rename.json = nil
        do_assert(uuid(), "3.7.0", expected_rt)

        -- cleanup
        admin.plugins:remove({ id = rt.id })
      end)

      it("does not remove `config.rename.json` from DP nodes that are already compatible", function()
        local rt = admin.plugins:insert {
          name = "response-transformer",
          enabled = true,
          config = {
            rename = {
              -- [[ new fields 3.8.0
              json = {"old:new"}
              -- ]]
            }
          }
        }
        do_assert(uuid(), "3.8.0", rt)

        -- cleanup
        admin.plugins:remove({ id = rt.id })
      end)
    end)
  end)
end)

end -- each strategy
