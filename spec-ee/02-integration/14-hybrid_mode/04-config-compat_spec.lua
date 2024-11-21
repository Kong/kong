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
local ee_helpers = require "spec-ee.helpers"
local get_portal_and_vitals_key = ee_helpers.get_portal_and_vitals_key
local join = require("pl.stringx").join
local pl_tablex = require("pl.tablex")
local clear_license_env = require("spec-ee.helpers").clear_license_env
local pl_file = require("pl.file")

local admin = require "spec.fixtures.admin_api"

local fmt = string.format

local CP_HOST = "127.0.0.1"
local CP_PORT = 9005

local PLUGIN_LIST

local EMPTY = {}

local idp_cert =
  "MIIC8DCCAdigAwIBAgIQLc/POHQrTIVD4/5aCN/6gzANBgkqhkiG9w0BAQsFADA0MTIwMAYDVQQD " ..
  "EylNaWNyb3NvZnQgQXp1cmUgRmVkZXJhdGVkIFNTTyBDZXJ0aWZpY2F0ZTAeFw0yMjA5MjcyMDE1 " ..
  "MzRaFw0yNTA5MjcyMDE1MzRaMDQxMjAwBgNVBAMTKU1pY3Jvc29mdCBBenVyZSBGZWRlcmF0ZWQg U" ..
  "1NPIENlcnRpZmljYXRlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv/P9hU7mjKFH " ..
  "9IxVGQt52p40Vj9lwMLBfrVc9uViCyCLILhGWz0kYbodpBtPkaYMrpJKSvaDD/Pop2Har+3gY1xB " ..
  "x3UAfLEZpb/ng+fM3AKQYRVH8rdfhtRMVx+mAus5oO/+7ca1ZhKeQpZtrSNBMSooBUFt6LygaotX " ..
  "7oJOFKBjL8vRjf0EeI0ismXuATtwE+wUDAe7qdsehjeZAD4Y1SLXulzS4ug3xRHPl8J9ZQL2D5Fp " ..
  "zRXgxX9SUpJ/iwxAj+q3igLmXMUeusCe6ugGrZ4Iz0QNq3v+VhGEhiX6DZByMhBnb1IIhpDBTUTq " ..
  "fxUno8GI1vh/w8liRldEkISZdQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAiw8VNBh5s2EVbDpJe " ..
  "kqEFT4oZdoDu3J4t1cHzst5Q3+XHWS0dndQh+R2xxVe072TKO/hn5ORlnw8Kp0Eq2g2YLpYvzt+k " ..
  "hbr/xQqMFhwZnaCCnoNLdoW6A9d7E3yDCnIK/7byfZ3484B4KrnzZdGF9eTFPcMBzyCU223S4R4z " ..
  "VYnNVfyqmlCaYUcYd9OnAbYZrbD9SPNqPSK/vPhn8aLzpn9huvcxpVYUMQ0+Mq680bse9tRu6Kbg " ..
  "SkaDNSe+xoE31OeWtR1Ko9Uhy6+Y7T1OQOi+BaNcIB1lXGivaudAVDh3mnKwSRw9vQ5y8m6kzFwE " ..
  "bkcl288gQ86BzUFaE36V"

local session_secret = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

-- We don't have running sentinel nodes config for specs - this is just a mock
local sentinel_node1 = { host = "localhost1", port = 26379 }
local sentinel_node2 = { host = "localhost2", port = 26380 }
local sentinel_node3 = { host = "localhost3", port = 26381 }
local sentinel_nodes = { sentinel_node1, sentinel_node2, sentinel_node3 }
local sentinel_addresses = {
  sentinel_node1.host .. ":" .. sentinel_node1.port,
  sentinel_node2.host .. ":" .. sentinel_node2.port,
  sentinel_node3.host .. ":" .. sentinel_node3.port,
}

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

local function get_vault(node_id, node_version, name)
  -- Emulates a DP connection to a CP. We're sending our node_id and version
  -- and expect a payload back that contains our sanitized plugin config.
  local res = cluster_client({ id = node_id, version = node_version })

  local vault
  if ((res or EMPTY).config_table or EMPTY).vaults then
    for _, p in ipairs(res.config_table.vaults) do
      if p.name == name then
        vault = p.config
        break
      end
    end
    assert.not_nil(vault, "vault " .. name .. " not found in config")
  end

  return vault, get_sync_status(node_id)
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

local ngx_null = ngx.null

local function is_present(value)
  return value and value ~= ngx_null
end

for _, strategy in helpers.each_strategy() do

describe("CP/DP config compat #" .. strategy, function()
  local db, reset_license_data

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
    reset_license_data = clear_license_env()
    helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))
    local bp
    local ENABLED_PLUGINS = { 'graphql-rate-limiting-advanced', 'ai-rate-limiting-advanced', 'rate-limiting-advanced', 'openid-connect',
    'oas-validation', 'mtls-auth', 'application-registration', "jwt-signer", "request-validator", 'proxy-cache-advanced', 'graphql-proxy-cache-advanced',
    'saml' }
    bp, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "clustering_data_planes",
      "vaults",
    }, ENABLED_PLUGINS)

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
      portal_and_vitals_key = get_portal_and_vitals_key(),
      nginx_conf = "spec/fixtures/custom_nginx.template",
      vaults = "bundled",
      plugins = "bundled," .. join(',', ENABLED_PLUGINS),
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    reset_license_data()
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
          traces_endpoint = "http://1.1.1.1:12345/v1/trace",
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
        label = "w/ unsupported fields",
        pending = false,
        config = {
          response_streaming = "allow",
          model = {
            provider = "azure",
            options = {
              azure_instance = "ai-proxy-regression",
              azure_deployment_id = "kong-gpt-3-5",
              upstream_path = "/v1/other-operation"
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
            config.auth.azure_tenant_id == nil and
            config.response_streaming == nil and
            config.model.options.upstream_path == nil
        end
      },
      {
        plugin = "ai-response-transformer",
        label = "w/ unsupported fields",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
                upstream_path = "/v1/other-operation"
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
            config.llm.auth.azure_tenant_id == nil and
            config.llm.model.options.upstream_path == nil
        end
      },
      {
        plugin = "ai-request-transformer",
        label = "w/ unsupported fields",
        pending = false,
        config = {
          prompt = "test",
          llm = {
            model = {
              provider = "azure",
              options = {
                azure_instance = "ai-proxy-regression",
                azure_deployment_id = "kong-gpt-3-5",
                upstream_path = "/v1/other-operation"
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
            config.llm.auth.azure_tenant_id == nil and
            config.llm.model.options.upstream_path == nil
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


  describe("request-validator for content_type_parameter_validation", function()
    local case_sanity = {
      plugin = "request-validator",
      label = "w/ content_type_parameter_validation",
      pending = false,
      config = {
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        content_type_parameter_validation = true,
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.content_type_parameter_validation == true
      end
    }

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.6.1.5")
    end)

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.7.1.0")
    end)

    local case = {
      plugin = "request-validator",
      label = "w/ api_spec_encoded unsupported",
      pending = false,
      config = {
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        content_type_parameter_validation = true,
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.content_type_parameter_validation == nil
      end
    }

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.6.1.4")
    end)

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.7.0.0")
    end)
  end)

  describe("aws-lambda plugin empty_arrays_mode", function()
    local case_sanity = {
      plugin = "aws-lambda",
      label = "w/ empty_arrays_mode",
      pending = false,
      config = {
        aws_key = "test",
        aws_secret = "test",
        aws_region = "us-east-1",
        function_name = "test-lambda",
        empty_arrays_mode = "correct",
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.empty_arrays_mode == "correct"
      end
    }

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.5.0.7")
    end)

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.6.1.7")
    end)

    it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
      do_assert(case_sanity, "3.7.1.2")
    end)

    local case = {
      plugin = "aws-lambda",
      label = "w/ empty_arrays_mode unsupported",
      pending = false,
      config = {
        aws_key = "test",
        aws_secret = "test",
        aws_region = "us-east-1",
        function_name = "test-lambda",
        empty_arrays_mode = "correct",
      },
      status = STATUS.NORMAL,
      validator = function(config)
        return config.empty_arrays_mode == nil
      end
    }

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.5.0.6")
    end)

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.6.1.6")
    end)

    it(fmt("%s - %s", case.plugin, case.label), function()
      do_assert(case, "3.7.1.1")
    end)
  end)

  describe("3.8.0.0", function()
    -- When the version of data-plane is lower than that of the control-plane it
    -- connects, DP should receive the config as described in the validator func
    describe("redis schema - connection_is_proxied", function()
      local dp_version = "3.7.9.9"
      local status = STATUS.NORMAL
      local validator = function(config)
        local rc = false
        if config.redis then
          rc = config.redis.connection_is_proxied == nil
        end
        return rc
      end
      -- 'connection_is_proxied' is only supported at '3.8.0.0' by the following plugins:
      -- rate-limiting-advanced | graphql-proxy-cache-advanced | graphql-rate-limiting-advanced |
      -- proxy-cache-advanced   | ai-rate-limiting-advanced | saml | openid-connect
      local cases = {
        {
          plugin = "rate-limiting-advanced",
          label = "w/ connection_is_proxied set to true",
          pending = false,
          config = {
            limit = { 1 },
            window_size = { 2 },
            sync_rate = 0.1,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = true,
            }
          },
          status = status,
          validator = validator
        },

        {
          plugin = "rate-limiting-advanced",
          label = "w/ connection_is_proxied set to false",
          pending = false,
          config = {
            limit = { 1 },
            window_size = { 2 },
            sync_rate = 0.1,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = false,
            }
          },
          status = status,
          validator = validator
        },

        {
          plugin = "proxy-cache-advanced",
          label = "w/ connection_is_proxied set to true",
          pending = false,
          config = {
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = true
            }
          },
          status = status,
          validator = validator
        },

        {
          plugin = "graphql-proxy-cache-advanced",
          label = "w/ connection_is_proxied set to true",
          pending = false,
          config = {
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = true
            }
          },
          status = status,
          validator = validator
        },

        {
          plugin = "ai-rate-limiting-advanced",
          label = "w/ connection_is_proxied set to true",
          pending = false,
          config = {
            llm_providers = {{
              name = "openai",
              window_size = 60,
              limit = 10,
            }},
            sync_rate = 10,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = true
            }
          },
          status = status,
          validator = validator
        },

        {
          plugin = "graphql-rate-limiting-advanced",
          label = "w/ connection_is_proxied set to true",
          pending = false,
          config = {
            limit = {1},
            window_size = {2},
            sync_rate = 0.1,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              connection_is_proxied = true
            }
          },
          status = status,
          validator = validator
        },

      }

      for i = 1, #cases do
        local case = cases[i]
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, dp_version)
        end)
      end

    end)

    -- When a data-plane lower than the version of the control-plane
    -- connects, it should receive the config as described in the validator func
    describe("redis changes - cluster_max_redirections", function()
      -- Shared redis config is used by:
      -- rate-limiting-advanced | graphql-rate-limiting-advanced | proxy-cache-advanced | graphql-proxy-cache-advanced
      local CASES = {
        {
          plugin = "rate-limiting-advanced",
          label = "w/ cluster_max_redirections configured",
          pending = false,
          config = {
            limit = {1},
            window_size = {2},
            sync_rate = 0.1,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              cluster_max_redirections = 10
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.redis.cluster_max_redirections == nil
          end
        },
        {
          plugin = "graphql-rate-limiting-advanced",
          label = "w/ cluster_max_redirections configured",
          pending = false,
          config = {
            limit = {1},
            window_size = {2},
            sync_rate = 0.1,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              cluster_max_redirections = 11
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.redis.cluster_max_redirections == nil
          end
        },
        {
          plugin = "ai-rate-limiting-advanced",
          label = "w/ cluster_max_redirections configured",
          pending = false,
          config = {
            llm_providers = {{
              name = "openai",
              window_size = 60,
              limit = 10,
            }},
            sync_rate = 10,
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              cluster_max_redirections = 10
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.redis.cluster_max_redirections == nil
          end
        },
        {
          plugin = "proxy-cache-advanced",
          label = "w/ cluster_max_redirections configured",
          pending = false,
          config = {
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              cluster_max_redirections = 12
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.redis.cluster_max_redirections == nil
          end
        },
        {
          plugin = "graphql-proxy-cache-advanced",
          label = "w/ cluster_max_redirections configured",
          pending = false,
          config = {
            strategy = "redis",
            redis = {
              host = helpers.redis_host,
              port = helpers.redis_port,
              cluster_max_redirections = 13
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.redis.cluster_max_redirections == nil
          end
        },

      }

      for _, case in ipairs(CASES) do
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.7.9.9")
        end)
      end
    end)

    describe("redis changes - cluster/sentinel_adresses to cluster/sentinel_nodes", function()
      -- Shared redis config is used by:
      -- rate-limiting-advanced | graphql-rate-limiting-advanced | proxy-cache-advanced |
      --    graphql-proxy-cache-advanced | ai-rate-limiting-advanced

      local function redis_cluster_addresses_validator(config)
        local pok = pcall(function() return assert.same(ee_helpers.redis_cluster_addresses, config.redis.cluster_addresses) end)
        return config.redis.cluster_nodes == nil and config.redis.redis_cluster_addresses ~= nil and pok
      end


      local function redis_sentinel_addresses_validator(config)
        local pok = pcall(function() return assert.same(sentinel_addresses, config.redis.sentinel_addresses) end)
        return config.redis.sentinel_nodes == nil and config.redis.sentinel_addresses ~= nil and pok
      end

      local plugins_config = {
        {
          plugin_name = "rate-limiting-advanced",
          plugin_config = {
            limit = {1},
            window_size = {2},
            sync_rate = 0.1,
            strategy = "redis",
          }
        },
        {
          plugin_name = "graphql-rate-limiting-advanced",
          plugin_config = {
            limit = {1},
            window_size = {2},
            sync_rate = 0.1,
            strategy = "redis",
          }
        },
        {
          plugin_name = "ai-rate-limiting-advanced",
          plugin_config = {
            llm_providers = {{
              name = "openai",
              window_size = 60,
              limit = 10,
            }},
            sync_rate = 10,
            strategy = "redis",
          }
        },
        {
          plugin_name = "proxy-cache-advanced",
          plugin_config = {
            strategy = "redis",
          }
        },
        {
          plugin_name = "graphql-proxy-cache-advanced",
          plugin_config = {
            strategy = "redis",
          }
        },
      }

      local CASES_CLUSTER_ADDRESSES = pl_tablex.map(function(config)
        return {
          plugin = config.plugin_name,
          label = "w/ cluster_nodes configured",
          pending = false,
          config = pl_tablex.merge(config.plugin_config,
            { redis = {
                cluster_nodes = ee_helpers.redis_cluster_nodes
            } }, true),
          status = STATUS.NORMAL,
          validator = redis_cluster_addresses_validator
        }
      end, plugins_config)

      local CASES_SENTINEL_ADDRESSES = pl_tablex.map(function(config)
        return {
          plugin = config.plugin_name,
          label = "w/ sentinel_nodes configured",
          pending = false,
          config = pl_tablex.merge(config.plugin_config,
            { redis = {
              sentinel_role = "master",
              sentinel_master = "localhost1",
              sentinel_nodes = sentinel_nodes
            } }, true),
          status = STATUS.NORMAL,
          validator = redis_sentinel_addresses_validator
        }
      end, plugins_config)


      local CASES = pl_tablex.merge(CASES_CLUSTER_ADDRESSES, CASES_SENTINEL_ADDRESSES, true)

      for _, case in ipairs(CASES) do
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.7.9.9")
        end)
      end
    end)

    describe("saml: redis changes - moving to shared redis schema", function()
      local cluster_nodes = {
        {
          ip = "redis-node-1",
          port = 6379,
        },
        {
          ip = "redis-node-2",
          port = 6380,
        },
        {
          ip = "127.0.0.1",
          port = 6381,
        },
      }

      local CASES = {
        {
          plugin = "saml",
          label = "w/ shared redis schema",
          pending = false,
          config = {
            issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
            assertion_consumer_path = "/consumer",
            idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
            idp_certificate = idp_cert,
            session_secret = session_secret,
            redis = {
              cluster_nodes = cluster_nodes,
            }
          },
          status = STATUS.NORMAL,
          validator = function(config)
            local pok = pcall(function() return assert.same(cluster_nodes, config.session_redis_cluster_nodes) end)
            return config.redis == nil and pok
          end
        },
      }

      for _, case in ipairs(CASES) do
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.7.9.9")
        end)
      end
    end)

    describe("plugins: compat", function()
      local CASES = {
        {
          plugin = "ai-rate-limiting-advanced",
          label = "w/ unsupported fields",
          pending = false,
          config = {
            strategy = "local",
            window_type = "fixed",
            llm_providers ={
              {
                name = "cohere",
                window_size = 30,
                limit = 1000,
              },
              {
                name = "gemini",
                window_size = 30,
                limit = 1000,
              },
              {
                name = "azure",
                window_size = 30,
                limit = 1000,
              },
              {
                name = "bedrock",
                window_size = 30,
                limit = 1000,
              },
            },
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.llm_providers[2].name == "requestPrompt"  -- replaces gemini
               and config.llm_providers[4].name == "requestPrompt"  -- replaces bedrock
          end
        },
      }

      for _, case in ipairs(CASES) do
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.7.9.9")
        end)
      end
    end)

    describe("redis: removes conflicting fields for older DPs", function ()
      describe("shared redis config plugins", function()
        local plugins_config = {
          {
            plugin_name = "rate-limiting-advanced",
            plugin_config = {
              limit = {1},
              window_size = {2},
              sync_rate = 0.1,
              strategy = "redis",
            }
          },
          {
            plugin_name = "graphql-rate-limiting-advanced",
            plugin_config = {
              limit = {1},
              window_size = {2},
              sync_rate = 0.1,
              strategy = "redis",
            }
          },
          {
            plugin_name = "ai-rate-limiting-advanced",
            plugin_config = {
              llm_providers = {{
                name = "openai",
                window_size = 60,
                limit = 10,
              }},
              sync_rate = 10,
              strategy = "redis",
            }
          },
          {
            plugin_name = "proxy-cache-advanced",
            plugin_config = {
              strategy = "redis",
            }
          },
          {
            plugin_name = "graphql-proxy-cache-advanced",
            plugin_config = {
              strategy = "redis",
            }
          }
        }

        describe("full config - cluster + sentinel + host/port", function()
          local CASES = pl_tablex.map(function(config)
            return {
              plugin = config.plugin_name,
              label = "w/ full config - cluster + sentinel + host/port configured",
              pending = false,
              config = pl_tablex.merge(config.plugin_config,
                { redis = {
                    cluster_nodes = ee_helpers.redis_cluster_nodes,
                    sentinel_nodes = sentinel_nodes,
                    sentinel_master = "mymaster",
                    sentinel_role = "master",
                    host = "127.0.0.5",
                    port = 6380
                } }, true),
              status = STATUS.NORMAL,
              validator = function(config)
                return is_present(config.redis.cluster_addresses) and
                        not is_present(config.redis.sentinel_addresses) and
                        not is_present(config.redis.sentinel_role) and
                        not is_present(config.redis.sentinel_master) and
                        not is_present(config.redis.host) and
                        not is_present(config.redis.port)
              end
            }
          end, plugins_config)

          for _, case in ipairs(CASES) do
            local test = case.pending and pending or it

            test(fmt("%s - %s", case.plugin, case.label), function()
              do_assert(case, "3.7.9.9")
            end)
          end
        end)

        describe("partial config - sentinel + host/port", function()
          local CASES = pl_tablex.map(function(config)
            return {
              plugin = config.plugin_name,
              label = "w/ partial config - sentinel + host/port configured",
              pending = false,
              config = pl_tablex.merge(config.plugin_config,
                { redis = {
                    sentinel_nodes = sentinel_nodes,
                    sentinel_master = "mymaster",
                    sentinel_role = "master",
                    host = "127.0.0.5",
                    port = 6380
                } }, true),
              status = STATUS.NORMAL,
              validator = function(config)
                return is_present(config.redis.sentinel_addresses) and
                       is_present(config.redis.sentinel_role) and
                       is_present(config.redis.sentinel_master) and
                        not is_present(config.redis.cluster_addresses) and
                        not is_present(config.redis.host) and
                        not is_present(config.redis.port)
              end
            }
          end, plugins_config)

          for _, case in ipairs(CASES) do
            local test = case.pending and pending or it

            test(fmt("%s - %s", case.plugin, case.label), function()
              do_assert(case, "3.7.9.9")
            end)
          end
        end)

        describe("empty redis config - default values are passed", function()
          local CASES = pl_tablex.map(function(config)
            return {
              plugin = config.plugin_name,
              label = "w/ empty redis config - default values are passed",
              pending = false,
              config = config.plugin_config,
              status = STATUS.NORMAL,
              validator = function(config)
                return is_present(config.redis.host) and
                       is_present(config.redis.port) and
                        not is_present(config.redis.sentinel_addresses) and
                        not is_present(config.redis.sentinel_role) and
                        not is_present(config.redis.sentinel_master) and
                        not is_present(config.redis.cluster_addresses)
              end
            }
          end, plugins_config)

          for _, case in ipairs(CASES) do
            local test = case.pending and pending or it

            test(fmt("%s - %s", case.plugin, case.label), function()
              do_assert(case, "3.7.9.9")
            end)
          end
        end)
      end)

      describe("saml and openid-connect", function()
        local CASES = {
          {
            plugin = "saml",
            label = "w/ full config - cluster + sentinel + host/port configured",
            pending = false,
            config = {
              issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
              assertion_consumer_path = "/consumer",
              idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
              idp_certificate = idp_cert,
              session_secret = session_secret,
              session_storage = "redis",
              redis = {
                cluster_nodes = ee_helpers.redis_cluster_nodes,
                sentinel_nodes = sentinel_nodes,
                sentinel_master = "mymaster",
                sentinel_role = "master",
                host = "127.0.0.5",
                port = 6380
              }
            },
            status = STATUS.NORMAL,
            validator = function(config)
              return is_present(config.session_redis_cluster_nodes) and
                      not is_present(config.session_redis_sentinel_nodes) and
                      not is_present(config.session_redis_sentinel_role) and
                      not is_present(config.session_redis_sentinel_master) and
                      not is_present(config.session_redis_host) and
                      not is_present(config.session_redis_port)
            end
          },
          {
            plugin = "saml",
            label = "w/ empty redis config - default values are passed",
            pending = false,
            config = {
              issuer = "https://samltoolkit.azurewebsites.net/kong_saml",
              assertion_consumer_path = "/consumer",
              idp_sso_url = "https://login.microsoftonline.com/f177c1d6-50cf-49e0-818a-a0585cbafd8d/saml2",
              idp_certificate = idp_cert,
              session_secret = session_secret,
              session_storage = "redis"
            },
            status = STATUS.NORMAL,
            validator = function(config)
              return is_present(config.session_redis_host) and
                      is_present(config.session_redis_port) and
                      not is_present(config.session_redis_sentinel_nodes) and
                      not is_present(config.session_redis_sentinel_role) and
                      not is_present(config.session_redis_sentinel_master) and
                      not is_present(config.session_redis_cluster_nodes)
            end
          },
          {
            plugin = "openid-connect",
            label = "w/ full config - cluster + sentinel + host/port configured",
            pending = false,
            config = {
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              session_storage = "redis",
              redis = {
                cluster_nodes = ee_helpers.redis_cluster_nodes,
                sentinel_nodes = sentinel_nodes,
                sentinel_master = "mymaster",
                sentinel_role = "master",
                host = "127.0.0.5",
                port = 6380
              }
            },
            status = STATUS.NORMAL,
            validator = function(config)
              return is_present(config.session_redis_cluster_nodes) and
                      not is_present(config.session_redis_sentinel_nodes) and
                      not is_present(config.session_redis_sentinel_role) and
                      not is_present(config.session_redis_sentinel_master) and
                      not is_present(config.session_redis_host) and
                      not is_present(config.session_redis_port)
            end
          },
          {
            plugin = "openid-connect",
            label = "w/ empty redis config - default values are passed",
            pending = false,
            config = {
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              session_storage = "redis",
            },
            status = STATUS.NORMAL,
            validator = function(config)
              return is_present(config.session_redis_host) and
                      is_present(config.session_redis_port) and
                      not is_present(config.session_redis_sentinel_nodes) and
                      not is_present(config.session_redis_sentinel_role) and
                      not is_present(config.session_redis_sentinel_master) and
                      not is_present(config.session_redis_cluster_nodes)
            end
          }
        }

        for _, case in ipairs(CASES) do
          local test = case.pending and pending or it

          test(fmt("%s - %s", case.plugin, case.label), function()
            do_assert(case, "3.7.9.9")
          end)
        end
      end)
    end)

    describe("#sts endpoint url in aws vault and aws-lambda plugin", function ()
      describe("aws-lambda plugin aws_sts_endpoint_url", function()
        local case_sanity = {
          plugin = "aws-lambda",
          label = "w/ aws_sts_endpoint_url",
          pending = false,
          config = {
            aws_key = "test",
            aws_secret = "test",
            aws_region = "us-east-1",
            function_name = "test-lambda",
            aws_sts_endpoint_url = "https://test.com",
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.aws_sts_endpoint_url == "https://test.com"
          end
        }

        it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
          do_assert(case_sanity, "3.5.0.8")
        end)

        it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
          do_assert(case_sanity, "3.6.1.8")
        end)

        it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
          do_assert(case_sanity, "3.7.1.3")
        end)

        it(fmt("%s - %s", case_sanity.plugin, case_sanity.label), function()
          do_assert(case_sanity, "3.8.0.0")
        end)

        local case = {
          plugin = "aws-lambda",
          label = "w/ aws_sts_endpoint_url unsupported",
          pending = false,
          config = {
            aws_key = "test",
            aws_secret = "test",
            aws_region = "us-east-1",
            function_name = "test-lambda",
            aws_sts_endpoint_url = "https://test.com",
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.aws_sts_endpoint_url == nil
          end
        }

        it(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.5.0.7")
        end)

        it(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.6.1.7")
        end)

        it(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.7.1.2")
        end)
      end)

      describe("aws vault sts_endpoint_url", function ()
        local function do_assert(case, dp_version)
          assert(db:truncate("sm_vaults"))
          assert(db:truncate("clustering_data_planes"))

          local vault_entity = {
            name = case.vault,
            prefix = "aws-test",
            config = case.config,
          }

          admin.vaults:insert(vault_entity)

          local id = utils.uuid()
          local conf, status
          helpers.wait_until(function()
            conf, status = get_vault(id, dp_version, case.vault)
            return status == case.status
          end, 5, 0.25)

          assert.equals(case.status, status)

          if case.validator then
            assert.is_truthy(case.validator(conf), "unexpected config received")
          end
        end

        local case_sanity = {
          vault = "aws",
          label = "w/ sts_endpoint_url supported",
          pending = false,
          config = {
            region = "us-east-1",
            assume_role_arn = "arn:aws:iam::123456789012:role/test-role",
            sts_endpoint_url = "https://test.com"
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.sts_endpoint_url == "https://test.com"
          end
        }

        it(fmt("%s - %s", case_sanity.vault, case_sanity.label), function()
          do_assert(case_sanity, "3.5.0.8")
        end)

        it(fmt("%s - %s", case_sanity.vault, case_sanity.label), function()
          do_assert(case_sanity, "3.6.1.8")
        end)

        it(fmt("%s - %s", case_sanity.vault, case_sanity.label), function()
          do_assert(case_sanity, "3.7.1.3")
        end)

        it(fmt("%s - %s", case_sanity.vault, case_sanity.label), function()
          do_assert(case_sanity, "3.8.0.0")
        end)

        local case = {
          vault = "aws",
          label = "w/ sts_endpoint_url unsupported",
          pending = false,
          config = {
            region = "us-east-1",
            assume_role_arn = "arn:aws:iam::123456789012:role/test-role",
            sts_endpoint_url = "https://test.com"
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.sts_endpoint_url == nil
          end
        }

        it(fmt("%s - %s", case.vault, case.label), function()
          do_assert(case, "3.5.0.7")
        end)

        it(fmt("%s - %s", case.vault, case.label), function()
          do_assert(case, "3.6.1.7")
        end)

        it(fmt("%s - %s", case.vault, case.label), function()
          do_assert(case, "3.7.1.2")
        end)

      end)
    end)
  end)

  describe("3.9.0.0", function()
    describe("plugins: compat", function()
      local CASES = {
        {
          plugin = "openid-connect",
          label = "w/ unsupported fields",
          pending = false,
          config = {
            issuer = "https://keycloak/realms/foo",
            auth_methods = {
              "authorization_code",
            },
            introspection_post_args_client_headers = {
              [1] = "header-one",
              [2] = "header-two",
            },
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.introspection_post_args_client_headers == nil
          end
        },
        {
          plugin = "ai-proxy-advanced",
          label = "w/ embeddings.model.name openai set to freehand text field",
          pending = false,
          config = {
            embeddings = {
              model = {
                name = "freehand-text-entry",
                provider = "openai",
              },
              auth = {
                header_name = "Authorization",
                header_value = "A",
              },
            },
            targets = {
              {
                weight = 50,
                route_type = "llm/v1/chat",
                model = {
                  provider = "cohere",
                  name = "command-light",
                },
              },
            },
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.embeddings.model.name == "text-embedding-3-small"
          end
        },
        {
          plugin = "ai-proxy-advanced",
          label = "w/ embeddings.model.name mistral set to freehand text field",
          pending = false,
          config = {
            embeddings = {
              model = {
                name = "freehand-text-entry",
                provider = "mistral",
              },
              auth = {
                header_name = "Authorization",
                header_value = "A",
              },
            },
            targets = {
              {
                weight = 50,
                route_type = "llm/v1/chat",
                model = {
                  provider = "cohere",
                  name = "command-light",
                },
              },
            },
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.embeddings.model.name == "mistral-embed"
          end
        },
        {
          plugin = "ai-proxy-advanced",
          label = "w/ embeddings.model.name openai ignores old supported value",
          pending = false,
          config = {
            embeddings = {
              model = {
                name = "text-embedding-3-large",
                provider = "openai",
              },
              auth = {
                header_name = "Authorization",
                header_value = "A",
              },
            },
            targets = {
              {
                weight = 50,
                route_type = "llm/v1/chat",
                model = {
                  provider = "cohere",
                  name = "command-light",
                },
              },
            },
          },
          status = STATUS.NORMAL,
          validator = function(config)
            return config.embeddings.model.name == "text-embedding-3-large"
          end
        },
      }

      for _, case in ipairs(CASES) do
        local test = case.pending and pending or it

        test(fmt("%s - %s", case.plugin, case.label), function()
          do_assert(case, "3.8.9.9")
        end)
      end
    end)
  end)
end)

end -- each strategy
