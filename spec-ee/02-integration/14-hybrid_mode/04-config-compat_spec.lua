-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS
local FIELDS = require("kong.clustering.compat.removed_fields")
local tablex = require "pl.tablex"

local admin = require "spec.fixtures.admin_api"

local fmt = string.format

local CP_HOST = "127.0.0.1"
local CP_PORT = 9005

local PLUGIN_LIST

local EMPTY = {}


local function cluster_client(opts)
  opts = opts or {}

  local _, res = pcall(helpers.clustering_client, {
    host = CP_HOST,
    port = CP_PORT,
    cert = "spec/fixtures/kong_clustering.crt",
    cert_key = "spec/fixtures/kong_clustering.key",
    node_hostname = opts.hostname or "test",
    node_id = opts.id or utils.uuid(),
    node_version = opts.version,
    node_plugins_list = PLUGIN_LIST,
  })

  return res
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


local function get_plugin(node_id, node_version, name)
  -- Emulates a DP connection to a CP. We're sending our node_id and version
  -- and expect a payload back that contains our sanitized plugin config.
  local res = cluster_client({ id = node_id, version = node_version })

  local plugin
  if ((res or EMPTY).config_table or EMPTY).plugins then
    for _, p in ipairs(res.config_table.plugins) do
      if p.name == name then
        plugin = p.config
        break
      end
    end
    assert.not_nil(plugin, "plugin " .. name .. " not found in config")
  end

  return plugin, get_sync_status(node_id)
end

for _, strategy in helpers.each_strategy() do

describe("CP/DP config compat #" .. strategy, function()
  local db

  local function do_assert(case, dp_version)
    assert(db:truncate("plugins"))
    assert(db:truncate("clustering_data_planes"))

    local plugin_entity = {
      name = case.plugin,
      config = case.config,
    }

    plugin_entity = case.init_plugin and case.init_plugin(plugin_entity) or plugin_entity

    local plugin = admin.plugins:insert(plugin_entity)
    assert.partial_match(case.config, plugin.config, "initial plugin configuration isn't sane.")

    local id = utils.uuid()
    local conf, status
    helpers.wait_until(function()
      -- Connect to a CP and await config.
      -- The config should be shaped as described in the validator func
      -- as the get_plugin function connects to the CP, which
      -- runs the required compatibility checkers (functions)
      -- to ensure a compatible config is sent back to us.
      conf, status = get_plugin(id, dp_version, case.plugin)
      return status == case.status
    end, 5, 0.25)

    assert.equals(case.status, status)

    if case.validator then
      assert.is_truthy(case.validator(conf), "unexpected config received")
    end
  end

  lazy_setup(function()
    local bp
    bp, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "clustering_data_planes",
    }, { 'graphql-rate-limiting-advanced', 'ai-rate-limiting-advanced', 'rate-limiting-advanced', 'openid-connect',
        'oas-validation', 'mtls-auth', 'application-registration', "jwt-signer" })

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
        plugins =
        [[
          bundled,graphql-rate-limiting-advanced,ai-rate-limiting-advanced,rate-limiting-advanced,
          openid-connect,oas-validation,mtls-auth,application-registration,
          jwt-signer
        ]],
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("3.4.x.y", function()
    -- When a data-plane lower than the version of the control-plane
    -- connects, it should receive the config as described in the validator func
    local CASES = {
      {
        plugin = "opentelemetry",
        label = "w/ header_type datadog unsupported",
        pending = false,
        config = {
          endpoint = "http://1.1.1.1:12345/v1/trace",
          header_type = "datadog"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.header_type == 'preserve'
        end
      }
    }

    for _, case in ipairs(CASES) do
      local test = case.pending and pending or it

      test(fmt("%s - %s", case.plugin, case.label), function()
        do_assert(case, "3.3.9.9")
      end)
    end
  end)

  describe("3.5.x.y", function()
    -- When a data-plane lower than the version of the control-plane
    -- connects, it should receive the config as described in the validator func
    local CASES = {
      {
        plugin = "acl",
        label = "w/ include_consumer_groups is unsupported",
        pending = false,
        config = {
          include_consumer_groups = true,
          allow = {"foo"}
        },
        status = STATUS.NORMAL,
        removed = FIELDS[3006000000].acl,
        validator = function(config)
          return config.include_consumer_groups == nil
        end
      }
    }

    for _, case in ipairs(CASES) do
      local test = case.pending and pending or it

      test(fmt("%s - %s", case.plugin, case.label), function()
        do_assert(case, "3.4.9.9")
      end)
    end
  end)

  describe("3.6.x.y", function()
    -- When a data-plane lower than the version of the control-plane
    -- connects, it should receive the config as described in the validator func
    local CASES = {
      {
        plugin = "rate-limiting-advanced",
        label = "w/ identifier consumer-group unsupported",
        pending = false,
        config = {
          limit = {1},
          window_size = {2},
          identifier = "consumer-group",
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.identifier == 'consumer'
        end
      },
      {
        plugin = "rate-limiting",
        label = "w/ limit_by consumer-group unsupported",
        pending = false,
        config = {
          second = 1,
          limit_by = "consumer-group"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.limit_by == 'consumer'
        end
      },
      {
        plugin = "openid-connect",
        label = "w/ unsupported client auth methods",
        pending = false,
        config = {
          issuer = "https://test.test",
          client_auth = {
            "client_secret_post",
            "client_secret_basic",
            "tls_client_auth",
            "self_signed_tls_client_auth"
          },
          tls_client_auth_cert_id            = "821a7065-ebce-43a2-adb6-2dcb1a3d6ef9",
          token_endpoint_auth_method         = "tls_client_auth",
          introspection_endpoint_auth_method = "self_signed_tls_client_auth",
          revocation_endpoint_auth_method    = "self_signed_tls_client_auth"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return tablex.compare({ "client_secret_post", "client_secret_basic" }, config.client_auth, "==") and
          config.token_endpoint_auth_method         == nil and
          config.introspection_endpoint_auth_method == nil and
          config.revocation_endpoint_auth_method    == nil
        end
      },

    }

    for _, case in ipairs(CASES) do
      local test = case.pending and pending or it

      test(fmt("%s - %s", case.plugin, case.label), function()
        do_assert(case, "3.5.9.9")
      end)
    end
  end)

  describe("oas-validation", function()
    local case_sanity = {
      plugin = "oas-validation",
      label = "w/ api_spec_encoded unsupported",
      pending = false,
      config = {
        api_spec = '{}',
        api_spec_encoded = true
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.api_spec_encoded == true
      end
    }

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.6.1.2")
    end)

    local case = {
      plugin = "oas-validation",
      label = "w/ api_spec_encoded unsupported",
      pending = false,
      config = {
        api_spec = '{}',
        api_spec_encoded = true
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.api_spec_encoded == nil
      end
    }

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.6.1.1")
    end)

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.5.0.3")
    end)

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.4.3.5")
    end)
  end)

  describe("3.7.x.y", function()
    -- When a data-plane lower than the version of the control-plane
    -- connects, it should receive the config as described in the validator func
    local CASES = {
      {
        plugin = "openid-connect",
        label = "w/ unsupported response_mode: query.jwt",
        pending = false,
        config = {
          issuer = "https://test.test",
          response_mode = "query.jwt"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.response_mode == "query"
        end
      },
      {
        plugin = "openid-connect",
        label = "w/ unsupported response_mode: form_post.jwt",
        pending = false,
        config = {
          issuer = "https://test.test",
          response_mode = "form_post.jwt"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.response_mode == "form_post"
        end
      },
      {
        plugin = "openid-connect",
        label = "w/ unsupported response_mode: fragment.jwt",
        pending = false,
        config = {
          issuer = "https://test.test",
          response_mode = "fragment.jwt"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.response_mode == "fragment"
        end
      },
      {
        plugin = "openid-connect",
        label = "w/ unsupported response_mode: jwt",
        pending = false,
        config = {
          issuer = "https://test.test",
          response_mode = "jwt"
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.response_mode == "query"
        end
      },
      {
        plugin = "jwt-signer",
        label = "w/ client auth and rotate_period unsupported",
        pending = false,
        config = {
          access_token_jwks_uri_client_username = "john",
          access_token_jwks_uri_client_password = "12345678",
          access_token_jwks_uri_client_certificate = { id = "10e2442e-7135-436b-b05d-e3319c030bd3" },
          access_token_jwks_uri_rotate_period = 300,
          access_token_keyset_client_username = "john",
          access_token_keyset_client_password = "12345678",
          access_token_keyset_client_certificate = { id = "10e2442e-7135-436b-b05d-e3319c030bd3" },
          access_token_keyset_rotate_period = 300,
          channel_token_jwks_uri_client_username = "john",
          channel_token_jwks_uri_client_password = "12345678",
          channel_token_jwks_uri_client_certificate = { id = "10e2442e-7135-436b-b05d-e3319c030bd3" },
          channel_token_jwks_uri_rotate_period = 300,
          channel_token_keyset_client_username = "john",
          channel_token_keyset_client_password = "12345678",
          channel_token_keyset_client_certificate = { id = "10e2442e-7135-436b-b05d-e3319c030bd3" },
          channel_token_keyset_rotate_period = 300,
        },
        status = STATUS.NORMAL,
        removed = FIELDS[3007000000].jwt_signer,
        validator = function(config)
          return config.access_token_jwks_uri_client_username == nil and
            config.access_token_jwks_uri_client_password == nil and
            config.access_token_jwks_uri_client_certificate == nil and
            config.access_token_jwks_uri_rotate_period == nil and
            config.access_token_keyset_client_username == nil and
            config.access_token_keyset_client_password == nil and
            config.access_token_keyset_client_certificate == nil and
            config.access_token_keyset_rotate_period == nil and
            config.channel_token_jwks_uri_client_username == nil and
            config.channel_token_jwks_uri_client_password == nil and
            config.channel_token_jwks_uri_client_certificate == nil and
            config.channel_token_jwks_uri_rotate_period == nil and
            config.channel_token_keyset_client_username == nil and
            config.channel_token_keyset_client_password == nil and
            config.channel_token_keyset_client_certificate == nil and
            config.channel_token_keyset_rotate_period == nil
        end
      },
      {
        plugin = "ai-proxy",
        label = "w/ unsupported azure managed identity",
        pending = false,
        config = {
          model = {
            provider = "azure",
            options = {
              azure_instance = "ai-proxy-regression",
              azure_deployment_id = "kong-gpt-3-5",
            },
            name = "kong-gpt-3-5"
          },
          auth = {
            azure_use_managed_identity = true,
            azure_client_id = "foo",
            azure_client_secret = "bar",
            azure_tenant_id = "baz"
          },
          route_type = "llm/v1/chat",
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.auth.azure_use_managed_identity == nil and
            config.auth.azure_client_id == nil and
            config.auth.azure_client_secret == nil and
            config.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-response-transformer",
        label = "w/ unsupported azure managed identity",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
              },
              name = "kong-gpt-3-5"
            },
            auth = {
              azure_use_managed_identity = true,
              azure_client_id = "foo",
              azure_client_secret = "bar",
              azure_tenant_id = "baz"
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.auth.azure_use_managed_identity == nil and
            config.llm.auth.azure_client_id == nil and
            config.llm.auth.azure_client_secret == nil and
            config.llm.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-request-transformer",
        label = "w/ unsupported azure managed identity",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
              },
              name = "kong-gpt-3-5"
            },
            auth = {
              azure_use_managed_identity = true,
              azure_client_id = "foo",
              azure_client_secret = "bar",
              azure_tenant_id = "baz"
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.auth.azure_use_managed_identity == nil and
            config.llm.auth.azure_client_id == nil and
            config.llm.auth.azure_client_secret == nil and
            config.llm.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-request-transformer",
        label = "w/ unsupported extra fields",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "openai",
              options = {
                max_tokens = 256,
                upstream_path = "/v1/other-operation"
              },
              name = "gpt-4"
            },
            auth = {
              header_name = "Authorization",
              header_value = "Bearer abc",
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.model.options.upstream_path == nil
        end
      },
      {
        plugin = "ai-proxy",
        label = "w/ unsupported azure managed identity set to false",
        pending = false,
        config = {
          model = {
            provider = "azure",
            options = {
              azure_instance = "ai-proxy-regression",
              azure_deployment_id = "kong-gpt-3-5",
            },
            name = "kong-gpt-3-5"
          },
          auth = {
            azure_use_managed_identity = false,
            azure_client_id = "foo",
            azure_client_secret = "bar",
            azure_tenant_id = "baz"
          },
          route_type = "llm/v1/chat",
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.auth.azure_use_managed_identity == nil and
            config.auth.azure_client_id == nil and
            config.auth.azure_client_secret == nil and
            config.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-proxy",
        label = "w/ unsupported extra fields",
        pending = false,
        config = {
          response_streaming = "allow",
          model = {
            provider = "openai",
            options = {
              max_tokens = 256,
              upstream_path = "/v1/other-operation"
            },
            name = "gpt-4"
          },
          auth = {
            header_name = "Authorization",
            header_value = "Bearer abc",
          },
          route_type = "llm/v1/chat",
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.response_streaming == nil and
            config.model.options.upstream_path == nil
        end
      },
      {
        plugin = "ai-request-transformer",
        label = "w/ unsupported azure managed identity set to false",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
              },
              name = "kong-gpt-3-5"
            },
            auth = {
              azure_use_managed_identity = false,
              azure_client_id = "foo",
              azure_client_secret = "bar",
              azure_tenant_id = "baz"
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.auth.azure_use_managed_identity == nil and
            config.llm.auth.azure_client_id == nil and
            config.llm.auth.azure_client_secret == nil and
            config.llm.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-response-transformer",
        label = "w/ unsupported azure managed identity set to false",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
              },
              name = "kong-gpt-3-5"
            },
            auth = {
              azure_use_managed_identity = false,
              azure_client_id = "foo",
              azure_client_secret = "bar",
              azure_tenant_id = "baz"
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.auth.azure_use_managed_identity == nil and
            config.llm.auth.azure_client_id == nil and
            config.llm.auth.azure_client_secret == nil and
            config.llm.auth.azure_tenant_id == nil
        end
      },
      {
        plugin = "ai-response-transformer",
        label = "w/ unsupported extra fields",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "openai",
              options = {
                max_tokens = 256,
                upstream_path = "/v1/other-operation"
              },
              name = "gpt-4"
            },
            auth = {
              header_name = "Authorization",
              header_value = "Bearer abc",
            },
            route_type = "llm/v1/chat",
          },
        },
        status = STATUS.NORMAL,
        validator = function(config)
          return config.llm.model.options.upstream_path == nil
        end
      },
    }

    for _, case in ipairs(CASES) do
      local test = case.pending and pending or it

      test(fmt("%s - %s", case.plugin, case.label), function()
        do_assert(case, "3.6.9.9")
      end)
    end
  end)

  describe("application-registration", function()
    local case = {
      plugin = "application-registration",
      label = "w/ unsupported enable_proxy_with_consumer_credential",
      pending = false,
      config = {
        enable_proxy_with_consumer_credential = false,
        display_name = "test.service",
      },
      status = STATUS.NORMAL,
      init_plugin = function(plugin)
        local service = admin.services:insert()
        plugin["service"] = service
        return plugin
      end,
      validator = function(config)
        return config.enable_proxy_with_consumer_credential == nil
      end
    }

    it(fmt("%s - %s - 3.6.1.3", case.plugin, case.label), function()
      do_assert(case, "3.6.1.3")
    end)

    it(fmt("%s - %s - 3.5.0.4", case.plugin, case.label), function()
      do_assert(case, "3.5.0.4")
    end)

    it(fmt("%s - %s - 3.4.3.6", case.plugin, case.label), function()
      do_assert(case, "3.4.3.6")
    end)
  end)

  describe("3.7.0.0", function()
    local unsupported = {
      plugin = "mtls-auth",
      label = "w/ default_consumer is unsupported",
      pending = false,
      config = {
        ca_certificates = {"00e2341e-0835-4d6b-855d-23c92d232bc4"},
        default_consumer = "281c2046-9480-4bee-8851-69362b1e8894"
      },
      status = STATUS.NORMAL,
      validator = function(config)
        local ca_certificate = "00e2341e-0835-4d6b-855d-23c92d232bc4"
        return config.default_consumer == nil and
          config.ca_certificates[1] == ca_certificate
      end
    }

    it(fmt("%s - %s", unsupported.plugin, unsupported.label), function()
      do_assert(unsupported, "3.4.3.4")
      do_assert(unsupported, "3.5.0.3")
      do_assert(unsupported, "3.6.1.3")
    end)

    local supported = {
      plugin = "mtls-auth",
      label = "w/ default_consumer is supported",
      pending = false,
      config = {
        ca_certificates = {"00e2341e-0835-4d6b-855d-23c92d232bc4"},
        default_consumer = "281c2046-9480-4bee-8851-69362b1e8894"
      },
      status = STATUS.NORMAL,
      validator = function(config)
        local ca_certificate = "00e2341e-0835-4d6b-855d-23c92d232bc4"
        return config.default_consumer == "281c2046-9480-4bee-8851-69362b1e8894" and
          config.ca_certificates[1] == ca_certificate
      end
    }

    it(fmt("%s - %s", supported.plugin, supported.label), function()
      do_assert(supported, "3.4.3.5")
      do_assert(supported, "3.5.0.4")
      do_assert(supported, "3.6.1.4")
      do_assert(supported, "3.7.0.0")
    end)
  end)


end)

end -- each strategy

