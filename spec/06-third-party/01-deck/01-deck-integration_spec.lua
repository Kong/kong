-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_tablex = require "pl.tablex"
local cjson = require "cjson"
local ssl_fixtures = require "spec.fixtures.ssl"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local pl_union = pl_tablex.union
local pl_pairmap = pl_tablex.pairmap

local ADMIN_LISTEN = "127.0.0.1:9001"
local DECK_TAG = "latest"


-- some plugins define required config fields that do not have default values.
-- This table defines values for such fields to obtain a minimal configuration
-- to set up each plugin.
local function get_plugins_configs(service)
  return {
    ["tcp-log"] = {
      name = "tcp-log",
      config = {
        host = "127.0.0.1",
        port = 10000,
      }
    },
    ["post-function"] = {
      name = "post-function",
      config = {
        access = { "print('hello, world')" },
      }
    },
    ["pre-function"] = {
      name = "pre-function",
      config = {
        access = { "print('hello, world')" },
      }
    },
    ["acl"] = {
      name = "acl",
      config = {
        allow = { "test group" }
      }
    },
    ["oauth2"] = {
      name = "oauth2",
      config = {
        enable_password_grant = true
      }
    },
    ["azure-functions"] = {
      name = "azure-functions",
      config = {
        appname = "test",
        functionname = "test",
      }
    },
    ["udp-log"] = {
      name = "udp-log",
      config = {
        host = "test.test",
        port = 8123
      }
    },
    ["ip-restriction"] = {
      name = "ip-restriction",
      config = {
        allow = { "0.0.0.0" }
      }
    },
    ["file-log"] = {
      name = "file-log",
      config = {
        path = "/tmp/log.out"
      }
    },
    ["http-log"] = {
      name = "http-log",
      config = {
        http_endpoint = "http://test.test"
      }
    },
    ["acme"] = {
      name = "acme",
      config = {
        account_email = "test@test.test"
      },
    },
    ["rate-limiting"] = {
      name = "rate-limiting",
      config = {
        second = 1
      },
    },
    ["ai-request-transformer"] = {
      name = "ai-request-transformer",
      config = {
        prompt = "test",
        llm = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer cohere-key",
          },
          model = {
            name = "command",
            provider = "cohere",
          },
        },
      },
    },
    ["ai-prompt-guard"] = {
      name = "ai-prompt-guard",
      config = {
        allow_patterns = { "test" },
      },
    },
    ["response-ratelimiting"] = {
      name = "response-ratelimiting",
      config = {
        limits = {
          test = {
            second = 1,
          },
        },
      },
    },
    ["proxy-cache"] = {
      name = "proxy-cache",
      config = {
        strategy = "memory"
      },
    },
    ["opentelemetry"] = {
      name = "opentelemetry",
      config = {
        traces_endpoint = "http://test.test"
      },
    },
    ["loggly"] = {
      name = "loggly",
      config = {
        key = "123"
      },
    },
    ["ai-proxy"] = {
      name = "ai-proxy",
      config = {
        route_type = "llm/v1/chat",
        auth = {
          header_name = "Authorization",
          header_value = "Bearer openai-key",
        },
        model = {
          name = "gpt-3.5-turbo",
          provider = "openai",
          options = {
            upstream_url = "http://test.test"
          },
        },
      },
    },
    ["ai-prompt-template"] = {
      name = "ai-prompt-template",
      config = {
        templates = {
          [1] = {
            name = "developer-chat",
            template = "foo",
          },
        }
      },
    },
    ["ai-prompt-decorator"] = {
      name = "ai-prompt-decorator",
      config = {
        prompts = {
          prepend = {
            [1] = {
              role = "system",
              content = "Prepend text 1 here.",
            }
          }
        },
      },
    },
    ["ldap-auth"] = {
      name = "ldap-auth",
      config = {
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        ldap_host = "test"
      },
    },
    ["ai-response-transformer"] = {
      name = "ai-response-transformer",
      config = {
        prompt = "test",
        llm = {
          model = {
            provider = "cohere"
          },
          auth = {
            header_name = "foo",
            header_value = "bar"
          },
          route_type = "llm/v1/chat",
        },
      },
    },
    ["standard-webhooks"] = {
      name = "standard-webhooks",
      config = {
        secret_v1 = "test",
      },
    },
    ["redirect"] = {
      name = "redirect",
      config = {
        location = "https://example.com",
      }
    },
    ["proxy-cache-advanced"] = {
      name = "proxy-cache-advanced",
      config = {
        strategy = "memory",
      }
    },
    ["openid-connect"] = {
      name = "openid-connect",
      config = {
        issuer = "http://test.test",
      }
    },
    ["rate-limiting-advanced"] = {
      name = "rate-limiting-advanced",
      config = {
        window_size = { 10 },
        limit = { 10 },
      }
    },
    ["service-protection"] = {
      name = "service-protection",
      config = {
        window_size = { 10 },
        limit = { 10 },
      }
    },
    ["ldap-auth-advanced"] = {
      name = "ldap-auth-advanced",
      config = {
        attribute = "foo",
        base_dn = "foo",
        ldap_host = "http://test.test"
      }
    },
    ["request-validator"] = {
      name = "request-validator",
      config = {
        parameter_schema = { {
          name = "x-kong-name",
          ["in"] = "header",
          required = true,
        } }
      }
    },
    ["mtls-auth"] = {
      name = "mtls-auth",
      config = {
        ca_certificates = {}
      }
    },
    ["header-cert-auth"] = {
      name = "header-cert-auth",
      config = {
        ca_certificates = {},
        certificate_header_format = "base64_encoded",
        certificate_header_name = "some-header",
        secure_source = true,
      }
    },
    ["graphql-rate-limiting-advanced"] = {
      name = "graphql-rate-limiting-advanced",
      config = {
        limit = { 10 },
        sync_rate = 1,
        window_size = { 10 }
      }
    },
    ["kafka-log"] = {
      name = "kafka-log",
      config = {
        topic = "foo"
      }
    },
    ["kafka-upstream"] = {
      name = "kafka-upstream",
      config = {
        topic = "foo"
      }
    },
    ["opa"] = {
      name = "opa",
      config = {
        opa_path = "/foo"
      }
    },
    ["ai-azure-content-safety"] = {
      name = "ai-azure-content-safety",
      config = {
        content_safety_url = "http://test.test"
      }
    },
    ["konnect-application-auth"] = {
      name = "konnect-application-auth",
      config = {
        scope = "foo"
      }
    },
    ["saml"] = {
      name = "saml",
      config = {
        assertion_consumer_path = "/foo",
        idp_sso_url = "http://test.test",
        issuer = "http://test.test",
        session_secret = "testtesttesttesttesttesttesttest",
        validate_assertion_signature = false,
      }
    },
    ["oas-validation"] = {
      name = "oas-validation",
      config = {
        api_spec = "{}"
      }
    },
    ["application-registration"] = {
      name = "application-registration",
      config = {
        display_name = "foo",
      },
      service = { id = service.id }
    },
    ["ai-rate-limiting-advanced"] = {
      name = "ai-rate-limiting-advanced",
      config = {
        llm_providers = { {
          name = "requestPrompt",
          window_size = 10,
          limit = 10,
        } },
        request_prompt_count_function = "return \"hello\"",
      }
    },
    ["websocket-validator"] = {
      name = "websocket-validator",
      config = {
        client = {
          text = {
            type = "draft4",
            schema = "{}",
          },
        },
      },
    },
    ["oauth2-introspection"] = {
      name = "oauth2-introspection",
      config = {
        introspection_url = "http://test.test",
        authorization_value = "hello",
      },
    },
    ["mocking"] = {
      name = "mocking",
      config = {
        api_specification_filename = "foo"
      },
    },
    ["jq"] = {
      name = "jq",
      config = {
        request_jq_program = ".foo"
      }
    },
    ["websocket-size-limit"] = {
      name = "websocket-size-limit",
      config = {
        client_max_payload = 1
      }
    },
    ["jwe-decrypt"] = {
      name = "jwe-decrypt",
      config = {
        key_sets = { "foo" }
      }
    },
    ["exit-transformer"] = {
      name = "exit-transformer",
      config = {
        functions = {}
      }
    },
    ["forward-proxy"] = {
      name = "forward-proxy",
      config = {
        http_proxy_host = "test.test",
        http_proxy_port = 8123
      }
    },
    ["route-transformer-advanced"] = {
      name = "route-transformer-advanced",
      config = {
        host = "http://test.test"
      }
    },
    ["canary"] = {
      name = "canary",
      config = {
        upstream_uri = "http://test.test"
      }
    },
    ["ai-proxy-advanced"] = {
      name = "ai-proxy-advanced",
      config = {
        targets = {
          {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "Authorization",
              header_value = "Bearer openai-key",
            },
            model = {
              name = "gpt-3.5-turbo",
              provider = "openai",
              options = {
                upstream_url = "http://test.test"
              },
            },
          },
        },
      },
    },
    ["ai-semantic-prompt-guard"] = {
      name = "ai-semantic-prompt-guard",
      config = {
        rules = {
          allow_prompts = { "some" },
          deny_prompts = { "other" },
        },
        embeddings = {
          model = {
            provider = "openai",
            name = "text-embedding-3-large",
          },
        },
        vectordb = {
          dimensions = 1024,
          distance_metric = "cosine",
          strategy = "redis",
          threshold = 0.1,
        }
      },
    },
    ["ai-semantic-cache"] = {
      name = "ai-semantic-cache",
      config = {
        embeddings = {
          model = {
            provider = "openai",
            name = "text-embedding-3-large",
          },
        },
        vectordb = {
          dimensions = 1024,
          distance_metric = "cosine",
          strategy = "redis",
          threshold = 0.1,
        }
      },
    },
    ["upstream-oauth"] = {
      name = "upstream-oauth",
      config = {
        oauth = {
          token_endpoint = "http://test.test",
          client_id = "1",
          client_secret = "2",
        },
      }
    },
    ["confluent"] = {
      name = "confluent",
      config = {
        bootstrap_servers = {
          {
            host = "test",
            port = 123,
          },
        },
        topic = "test",
        cluster_api_key = "test",
        cluster_api_secret = "secret",
      },
    }
  }
end


-- pending plugins are not yet supported by deck
local pending = {
  ["vault-auth"] = true,
}


-- returns a list-like table of all plugins
local function get_all_plugins()
  return pl_pairmap(
    function(k, v)
      return type(k) ~= "number" and k or v
    end,
    pl_union(
      require("kong.constants").CE_PLUGINS_MAP,
      pl_union(
        require("kong.constants").EE_PLUGINS_MAP,
        require("distribution.distributions_constants").plugins
      )
    )
  )
end


local function get_docker_run_cmd(deck_command, config_dir, config_file)
  local cmd = "docker run -u $(id -u):$(id -g) " ..
      "-v " .. config_dir .. ":/tmp/cfg "        ..
      "--network host "                          ..
      "kong/deck:" .. DECK_TAG                   ..
      " gateway " .. deck_command                ..
      " --kong-addr http://" .. ADMIN_LISTEN

  if deck_command == "dump" then
    cmd = cmd .. " --with-id -o"
  end

  return cmd .. " /tmp/cfg/" .. config_file
end


for _, strategy in helpers.each_strategy({ "postgres" }) do
  describe("Deck tests", function()
    local admin_client, cleanup
    local plugins = get_all_plugins()
    local configured_plugins_num = 0

    local kong_env = {
      database     = strategy,
      nginx_conf   = "spec/fixtures/custom_nginx.template",
      plugins      = table.concat(plugins, ","),
      portal_and_vitals_key = get_portal_and_vitals_key(),
      admin_listen = ADMIN_LISTEN,
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, plugins)

      -- services and plugins
      local service = bp.services:insert {
        name = "example-service",
        host = "example.com"
      }
      local plugins_configs = get_plugins_configs(service)
      for _, plugin in ipairs(plugins) do
        if not pending[plugin] then
          local ok, err
          ok, err = pcall(
            bp.plugins.insert,
            bp.plugins,
            plugins_configs[plugin] or { name = plugin }
          )

          -- if this assertion fails make sure the plugin is configured
          -- correctly with the required fields in the `get_plugins_configs`
          -- function above
          assert(ok, "failed configuring plugin: " .. plugin .. " with error: "
                 .. tostring(err))
          configured_plugins_num = configured_plugins_num + 1
        end
      end

      -- other entities
      bp.routes:insert {
        hosts = { "example.com" },
        service = service,
      }
      local certificate = bp.certificates:insert {
        cert = ssl_fixtures.cert_alt_alt,
        key = ssl_fixtures.key_alt_alt,
        cert_alt = ssl_fixtures.cert_alt_alt_ecdsa,
        key_alt = ssl_fixtures.key_alt_alt_ecdsa,
      }
      bp.snis:insert {
        name = "example.test",
        certificate = certificate,
      }
      bp.ca_certificates:insert {
        cert = ssl_fixtures.cert_ca,
      }
      local upstream = bp.upstreams:insert()
      bp.targets:insert({
        upstream = upstream,
        target = "api-1:80",
      })
      bp.consumers:insert {
        username = "consumer"
      }
      bp.vaults:insert({
        name   = "env",
        prefix = "my-env-vault",
      })
      bp.consumer_groups:insert {
        name = "test_group"
      }

      assert(helpers.start_kong(kong_env))
      admin_client = helpers.admin_client()

      -- pull deck image
      local result = { os.execute("docker pull kong/deck:" .. DECK_TAG) }
      assert.same({ true, "exit", 0 }, result)
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
      if cleanup then
        cleanup()
      end
    end)

    it("execute `gateway dump` and `gateway sync` commands successfully", function()
      local config_file = "deck-config.yml"
      local config_dir
      config_dir, cleanup = helpers.make_temp_dir()

      -- dump the config
      local result = { os.execute(get_docker_run_cmd("dump", config_dir, config_file)) }
      assert.same({ true, "exit", 0 }, result)

      -- confirm the config file was created
      local f = io.open(config_dir .. "/" .. config_file, "r")
      assert(f and f:close())
      assert.not_nil(f)

      -- reset db
      helpers.get_db_utils(strategy, nil, plugins)
      helpers.restart_kong(kong_env)

      -- confirm db reset (no plugins are configured)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/plugins/",
      })
      local configured_plugins = cjson.decode(assert.res_status(200, res))
      assert.equals(0, #configured_plugins.data)

      -- sync the config
      result = { os.execute(get_docker_run_cmd("sync", config_dir, config_file)) }
      assert.same({ true, "exit", 0 }, result)

      -- confirm sync happened (all expected plugins are configured)
      res = assert(admin_client:send {
        method = "GET",
        path = "/plugins/",
      })
      configured_plugins = cjson.decode(assert.res_status(200, res))
      assert.equals(configured_plugins_num, #configured_plugins.data)
    end)
  end)
end
