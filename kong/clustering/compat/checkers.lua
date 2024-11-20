-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ipairs = ipairs
local table_remove = table.remove
local type = type
local cjson = require "cjson"
local version = require("kong.clustering.compat.version")
local version_num = version.string_to_number


local null = ngx.null
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN


local _log_prefix = "[clustering] "


local log_warn_message, _AI_PROVIDER_INCOMPATIBLE
do
  local fmt = string.format

  local KONG_VERSION = require("kong.meta").version

  log_warn_message = function(hint, action, dp_version, log_suffix)
    local msg = fmt("Kong Gateway v%s %s " ..
                    "which is incompatible with dataplane version %s " ..
                    "and will %s.",
                    KONG_VERSION, hint, dp_version, action)
    ngx_log(ngx_WARN, _log_prefix, msg, log_suffix)
  end

  local _AI_PROVIDERS_ADDED = {
    [3008000000] = {
      "gemini",
      "bedrock",
    },
  }

  _AI_PROVIDER_INCOMPATIBLE = function(provider, ver)
    for _, v in ipairs(_AI_PROVIDERS_ADDED[ver]) do
      if v == provider then
        return true
      end
    end

    return false
  end
end

local compatible_checkers = {
  { 3009000000, --[[ 3.9.0.0 ]]
    function(config_table, dp_version, log_suffix)

      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'ai-semantic-cache' then
          local consumer_group_scope = plugin["consumer_group"]
          if consumer_group_scope ~= cjson.null and consumer_group_scope ~= nil then
            has_update = true
            plugin.enabled = false

            log_warn_message('configures ' .. plugin.name .. ' plugin consumer_group scope',
                              'the entire plugin will be disabled on this dataplane node',
                              dp_version,
                              log_suffix)
          end
        end
      end

      return has_update
    end,
  },
  { 3008000000, --[[ 3.8.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update
      local dp_version_num = version_num(dp_version)
      local redis_plugins = {
        ["proxy-cache-advanced"] = true,
        ["graphql-proxy-cache-advanced"] = true,
        ["graphql-rate-limiting-advanced"] = true,
        ["rate-limiting-advanced"] = true,
        ["ai-rate-limiting-advanced"] = true,
        --[=[ the whole 'redis' object is already removed in 'removed_fields.lua'
        ["saml"] = true,
        ["openid-connect"] = true,
        --]=]
      }

      for _, plugin in ipairs(config_table.plugins or {}) do
        local plugin_name = plugin.name

        if plugin.name == 'acme' then
          local config = plugin.config
          if config.storage_config.redis.username ~= nil then
            log_warn_message('configures ' .. plugin.name .. ' plugin with redis username',
              'not work in this release',
              dp_version, log_suffix)
          end
        end

        if redis_plugins[plugin_name] then
          local config = plugin.config
          if config and config.redis then
            -- connection_is_proxied -----------------------
            if config.redis.connection_is_proxied ~= nil then
              config.redis.connection_is_proxied = nil
              has_update = true

              log_warn_message(
                "configures " .. plugin_name .. " plugin with 'connection_is_proxied'" ..
                ", will remove this field,",
                dp_version, log_suffix)
            end
            -- connection_is_proxied -----------------------

            -- conflicting host/port, cluster_nodes, sentinel_nodes -----------------------
            if config.redis.cluster_nodes and config.redis.cluster_nodes ~= ngx.null then
              if config.redis.host or config.redis.port or config.redis.sentinel_nodes then
                config.redis.host = nil
                config.redis.port = nil
                config.redis.sentinel_nodes = nil
                config.redis.sentinel_addresses = nil
                config.redis.sentinel_master = nil
                config.redis.sentinel_role = nil
                has_update = true

                log_warn_message(
                  "configures " .. plugin_name .. " plugin with 'redis host/port and sentinel_nodes'" ..
                  ", will clear those fields for older DPs to accept this config,", dp_version, log_suffix
                )
              end
            elseif config.redis.sentinel_nodes and config.redis.sentinel_nodes ~= ngx.null then
              if config.redis.host or config.redis.port then
                config.redis.host = nil
                config.redis.port = nil
                has_update = true

                log_warn_message(
                  "configures " .. plugin_name .. " plugin with 'redis host/port'" ..
                  ", will clear those fields for older DPs to accept this config,", dp_version, log_suffix
                )
              end
            end
          end
        end

        if plugin_name == "saml" or plugin_name == "openid-connect" then
          local config = plugin.config
          if config and config.redis then
            if config.redis.cluster_nodes and config.redis.cluster_nodes ~= ngx.null then
              if config.redis.host or config.redis.port then
                -- Entire config.redis block will be removed by `removed_fields` so there's no point in clearing it here
                -- config.redis.host = nil
                -- config.redis.port = nil

                config.session_redis_host = nil
                config.session_redis_port = nil

                has_update = true

                log_warn_message(
                  "configures " .. plugin_name .. " plugin with 'redis host/port and sentinel_nodes'" ..
                  ", will clear those fields for older DPs to accept this config,", dp_version, log_suffix
                )
              end

              -- No need to check redis.config.sentinel_nodes since before 3.8.0.0 saml and openid-connect
              -- did not support Redis Sentinel conifugration. Admin updates are forbidden during upgrade phase so
              -- it's impossible to have new CP (3.8) with a plugin configured to use ex: saml + Redis Sentinel
              -- and at the same time have an older DP (3.7)
            end
          end
        end

        if plugin_name == 'ai-rate-limiting-advanced' then
          local config = plugin.config
          if config.tokens_count_strategy == "cost" then
            -- remove cost strategy and replace with the default
            config.tokens_count_strategy = "total_tokens"
            log_warn_message('configures ' .. plugin_name .. ' plugin with tokens_count_strategy == cost',
                             'overwritten with default value `total_tokens`.',
                             dp_version, log_suffix)
            has_update = true
          end

          for i = #config.llm_providers, 1, -1 do
            local provider_name = config.llm_providers[i].name
            if provider_name == "gemini" or provider_name == "bedrock" then
              config.llm_providers[i].name = "requestPrompt"
              log_warn_message('configures ' .. plugin.name .. ' plugin with llm_providers[' .. i .. '].name == ' .. provider_name,
                              'overwritten with `requestPrompt`.',
                              dp_version, log_suffix)
              has_update = true
            end
          end

        end

        if plugin_name == 'aws-lambda' then
          local config = plugin.config
          if config.aws_sts_endpoint_url ~= nil then
            if dp_version_num < 3004003013 or
                (dp_version_num >= 3005000000 and dp_version_num < 3005000008) or
                (dp_version_num >= 3006000000 and dp_version_num < 3006001008) or
                (dp_version_num >= 3007000000 and dp_version_num < 3007001003) then
              config.aws_sts_endpoint_url = nil
              has_update = true
              log_warn_message('configures ' .. plugin_name .. ' plugin with aws_sts_endpoint_url',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end

        if plugin_name == 'ai-proxy' then
          local config = plugin.config
          if _AI_PROVIDER_INCOMPATIBLE(config.model.provider, 3008000000) then
            log_warn_message('configures ' .. plugin_name .. ' plugin with' ..
            ' "openai preserve mode", because ' .. config.model.provider .. ' provider ' ..
            ' is not supported in this release',
            dp_version, log_suffix)

            config.model.provider = "openai"
            config.route_type = "preserve"

            has_update = true
          end

          if config.model.provider == "mistral" and (
            not config.model.options or
            config.model.options == ngx.null or
            not config.model.options.upstream_url or
            config.model.options.upstream_url == ngx.null) then

            log_warn_message('configures ' .. plugin.name .. ' plugin with' ..
              ' mistral provider uses fallback upstream_url for managed serivice' ..
              dp_version, log_suffix)

            config.model.options = config.model.options or {}
            config.model.options.upstream_url = "https://api.mistral.ai:443"
            has_update = true
          end
        end

        if plugin_name == 'ai-request-transformer' then
          local config = plugin.config
          if _AI_PROVIDER_INCOMPATIBLE(config.llm.model.provider, 3008000000) then
            log_warn_message('configures ' .. plugin_name .. ' plugin with' ..
            ' "openai preserve mode", because ' .. config.llm.model.provider .. ' provider ' ..
            ' is not supported in this release',
            dp_version, log_suffix)

            config.llm.model.provider = "openai"

            has_update = true
          end
        end

        if plugin_name == 'ai-response-transformer' then
          local config = plugin.config
          if _AI_PROVIDER_INCOMPATIBLE(config.llm.model.provider, 3008000000) then
            log_warn_message('configures ' .. plugin_name .. ' plugin with' ..
            ' "openai preserve mode", because ' .. config.llm.model.provider .. ' provider ' ..
            ' is not supported in this release',
            dp_version, log_suffix)

            config.llm.model.provider = "openai"

            has_update = true
          end
        end

      end

      for _, vault in ipairs(config_table.vaults or {}) do
        local name = vault.name
        local config = vault.config
        if name == "aws" and config.sts_endpoint_url ~= nil then
          if dp_version_num < 3004003013 or
              (dp_version_num >= 3005000000 and dp_version_num < 3005000008) or
              (dp_version_num >= 3006000000 and dp_version_num < 3006001008) or
              (dp_version_num >= 3007000000 and dp_version_num < 3007001003) then
            log_warn_message('contains configuration vaults.aws.sts_endpoint_url',
                            'be removed',
                            dp_version, log_suffix)
            vault.config.sts_endpoint_url = nil
            has_update = true
          end
        end
      end

      return has_update
    end
  },
  {
    3007001002, --[[3.7.1.2]]
    function(config_table, dp_version, log_suffix)
      local has_update

      local dp_version_num = version_num(dp_version)

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == "aws-lambda" then
          local config = plugin.config
          if config.empty_arrays_mode ~= nil then
            if dp_version_num >= 3007000000 and dp_version_num < 3007001002 then
              -- remove config.empty_arrays_mode when DP version in interval [3700, 3712)
              config.empty_arrays_mode = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with empty_arrays_mode',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
      end

      return has_update
    end
  },
  {
    3007001000, --[[3.7.1.0]]
    function(config_table, dp_version, log_suffix)
      local has_update

      local dp_version_num = version_num(dp_version)

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'request-validator' then
          local config = plugin.config
          if config.content_type_parameter_validation ~= nil then
            if dp_version_num < 3006001005 or
              dp_version_num >= 3007000000 then
              -- remove config.content_type_parameter_validation when DP version in intervals (, 3615), [3700, 3710)
              config.content_type_parameter_validation = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with content_type_parameter_validation',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
      end

      return has_update
    end
  },
  { 3007000000, -- [[ 3.7.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'openid-connect' then
          local config = plugin.config
          if config.response_mode == 'query.jwt' or
             config.response_mode == 'jwt'       then
            config.response_mode = 'query'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' response_mode == query.jwt or jwt',
                             'overwritten with default value `query`',
                             dp_version, log_suffix)
            has_update = true

          elseif config.response_mode == 'form_post.jwt' then
            config.response_mode = 'form_post'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' response_mode == form_post.jwt',
                             'overwritten with default value `form_post`',
                             dp_version, log_suffix)
            has_update = true

          elseif config.response_mode == 'fragment.jwt' then
            config.response_mode = 'fragment'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' response_mode == fragment.jwt',
                             'overwritten with default value `fragment`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
        if plugin.name == 'graphql-proxy-cache-advanced' then
          local config = plugin.config
          if config.strategy == "redis" then
            config.strategy = "memory"
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' strategy == redis',
                             'overwritten with default value `memory`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
        if plugin.name == 'mtls-auth' then
          local dp_version_num = version_num(dp_version)
          local config = plugin.config
          if config.default_consumer ~= nil then
            if dp_version_num < 3004003005 or
               (dp_version_num >= 3005000000 and dp_version_num < 3005000004) or
               (dp_version_num >= 3006000000 and dp_version_num < 3006001004) then
              -- remove config.default_consumer when DP version in intervals (, 3435), [3500, 3504), [3600, 3614)
              config.default_consumer = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with default_consumer',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
        if plugin.name == 'ai-proxy' then
          local config = plugin.config
          if config.route_type == "preserve" then
            config.route_type = "llm/v1/chat"
            log_warn_message('configures ' .. plugin.name .. ' plugin with' ..
                              ' route_type == "llm/v1/chat", because preserve' ..
                              ' mode is not supported in this release',
                              dp_version, log_suffix)
            has_update = true
          end
        end

        if plugin.name == 'application-registration' then
          local config = plugin.config
          local dp_version_num = version_num(dp_version)

          if config.enable_proxy_with_consumer_credential ~= nil then
            if dp_version_num < 3004003007 or
                (dp_version_num >= 3005000000 and dp_version_num < 3005000005) or
                (dp_version_num >= 3006000000 and dp_version_num < 3006001004) then
              -- remove config.enable_proxy_with_consumer_credential when DP version in intervals (, 3437), [3500, 3505), [3600, 3614)
              config.enable_proxy_with_consumer_credential = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with enable_proxy_with_consumer_credential',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
      end -- end for

      return has_update
      end -- end function
  },
  {
    3006001007, --[[3.6.1.7]]
    function(config_table, dp_version, log_suffix)
      local has_update

      local dp_version_num = version_num(dp_version)

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == "aws-lambda" then
          local config = plugin.config
          if config.empty_arrays_mode ~= nil then
            if dp_version_num >= 3006000000 and dp_version_num < 3006001007 then
              -- remove config.empty_arrays_mode when DP version in interval [3600, 3617)
              config.empty_arrays_mode = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with empty_arrays_mode',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
      end

      return has_update
    end
  },
  { 3006001002, --[[3.6.1.2]]
    function(config_table, dp_version, log_suffix)
      local has_update

      local dp_version_num = version_num(dp_version)

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'oas-validation' then
          local config = plugin.config
          if config.api_spec_encoded ~= nil then
            if dp_version_num < 3004003006 or
              (dp_version_num >= 3005000000 and dp_version_num < 3005000004) or
              dp_version_num >= 3006000000 then
              -- remove config.api_spec_encoded when DP version in intervals (, 3436), [3500, 3504), [3600, 3612)
              config.api_spec_encoded = nil
              has_update = true
              log_warn_message('configures ' .. plugin.name .. ' plugin with api_spec_encoded',
                'will be removed.',
                dp_version, log_suffix)
            end
          end
        end
      end

      return has_update
    end
  },
  { 3006000000, -- [[ 3.6.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update
      local redis_plugins_update = {
        acme = require("kong.plugins.acme.clustering.compat.redis_translation").adapter,
        ['rate-limiting'] = require("kong.plugins.rate-limiting.clustering.compat.redis_translation").adapter,
        ['response-ratelimiting'] = require("kong.plugins.response-ratelimiting.clustering.compat.redis_translation").adapter
      }

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'rate-limiting-advanced' then
          local config = plugin.config
          if config.identifier == "consumer-group" then
            -- remove consumer-group identifier and replace with the default
            config.identifier = "consumer"
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' identifier == consumer-group',
                             'overwritten with default value `consumer`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
        if plugin.name == 'rate-limiting' then
          local config = plugin.config
          if config.limit_by == "consumer-group" then
            -- remove consumer-group limit_by and replace with the default
            config.limit_by = "consumer"
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' limit_by == consumer-group',
                             'overwritten with default value `consumer`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
        if plugin.name == 'openid-connect' then
          local config = plugin.config

          for _, config_val in ipairs({ "tls_client_auth", "self_signed_tls_client_auth" }) do

            if type(config.client_auth) == "table" then
              for i = #config.client_auth, 1, -1 do
                if config.client_auth[i] == config_val then
                  log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                                   ' client_auth containing: ' .. config_val,
                                   'removed',
                                   dp_version, log_suffix)
                  table_remove(config.client_auth, i)
                  has_update = true
                end
              end
            end

            for _, config_key in ipairs({ "token_endpoint_auth_method",
                                          "introspection_endpoint_auth_method",
                                          "revocation_endpoint_auth_method" }) do

              if config[config_key] == config_val then
                log_warn_message('configures ' .. plugin.name .. ' plugin with: ' ..
                                 config_key .. ' == ' .. config_val,
                                 'overwritten with default value `nil`',
                                 dp_version, log_suffix)
                config[config_key] = nil
                has_update = true
              end
            end
          end
        end

        local adapt_fn = redis_plugins_update[plugin.name]
        if adapt_fn and type(adapt_fn) == "function" then
          local adaptation_happened = adapt_fn(plugin.config)
          if adaptation_happened then
            has_update = true
            log_warn_message('adapts ' .. plugin.name .. ' plugin redis configuration to older version',
              'revert to older schema',
              dp_version, log_suffix)
          end
        end
      end

      return has_update
    end
  },

  {
    3005000007, --[[3.5.0.7]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == "aws-lambda" then
          local config = plugin.config
          if config.empty_arrays_mode ~= nil then
            -- remove config.empty_arrays_mode when DP version less than 3507
            config.empty_arrays_mode = nil
            has_update = true
            log_warn_message('configures ' .. plugin.name .. ' plugin with empty_arrays_mode',
              'will be removed.',
              dp_version, log_suffix)
          end
        end
      end

      return has_update
    end
  },

  { 3005000004, -- [[ 3.5.0.4 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      local dp_version_num = version_num(dp_version)
      -- remove approle fields from hcv vault when 3.5.0.0 <= dp_version < 3.5.0.4
      if dp_version_num >= 3005000000 then
        for _, vault in ipairs(config_table.vaults or {}) do
          local name = vault.name
          if name == "hcv" then
            for _, parameter in ipairs({"approle_auth_path", "approle_role_id", "approle_secret_id", "approle_secret_id_file", "approle_response_wrapping"}) do
              log_warn_message('contains configuration vaults.hcv.' .. parameter,
                              'be removed', dp_version, log_suffix)
              vault.config[parameter] = nil
              has_update = true
            end
          end
        end
      end

      return has_update
    end
  },

  { 3005000000, --[[ 3.5.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'opentelemetry' or plugin.name == 'zipkin' then
          local config = plugin.config
          if config.header_type == 'gcp' then
            config.header_type = 'preserve'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' header_type == gcp',
                             'overwritten with default value `preserve`',
                             dp_version, log_suffix)
            has_update = true
          end
        end

        if plugin.name == 'zipkin' then
          local config = plugin.config
          if config.default_header_type == 'gcp' then
            config.default_header_type = 'b3'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' default_header_type == gcp',
                             'overwritten with default value `b3`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
      end

      return has_update
    end
  },

  { 3004003005, --[[ 3.4.3.5 ]]
    function (config_table, dp_version, log_suffix)
      local has_update

      for _, vault in ipairs(config_table.vaults or {}) do
        local name = vault.name
        if name == "aws" then
          for _, parameter in ipairs({ "endpoint_url", "assume_role_arn", "role_session_name" }) do
            if vault.config[parameter] then
              log_warn_message('contains configuration vaults.aws.' .. parameter,
                               'be removed',
                               dp_version, log_suffix)
              vault.config[parameter] = nil
              has_update = true
            end
          end
        end
      end

      for _, vault in ipairs(config_table.vaults or {}) do
        local name = vault.name
        if name == "hcv" then
          for _, parameter in ipairs({"approle_auth_path", "approle_role_id", "approle_secret_id", "approle_secret_id_file", "approle_response_wrapping"}) do
            log_warn_message('contains configuration vaults.hcv.' .. parameter,
                            'be removed', dp_version, log_suffix)
            vault.config[parameter] = nil
            has_update = true
          end
        end
      end

      return has_update
    end
  },

  { 3004003004, --[[3.4.3.4]]
    function(config_table, dp_version, log_suffix)
      local has_update
      for _, vault in ipairs(config_table.vaults or {}) do
        local name = vault.name
        if name == "hcv" then
          if vault.config.kube_auth_path then
            vault.config.kube_auth_path = nil
            has_update = true
          end
        end
      end

      return has_update
    end
  },

  { 3004001000, --[[3.4.1.0]]
    function(config_table, dp_version, log_suffix)
      local has_update
      -- redis in cluster mode is not suppported until 3.4.1.0
      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'graphql-rate-limiting-advanced' then
          local config = plugin.config
          if config.strategy == 'redis' and config.redis.cluster_addresses then
            config.redis = nil
            config.strategy = 'cluster'
            config.sync_rate = -1
            has_update = true
            log_warn_message("redis cluster mode is not supported",
                             "be overwritten with config.strategy = cluster" ..
                             "and config.sync_rate = -1",
                             dp_version,
                             log_suffix)
          end

        elseif plugin.name == 'opentelemetry' then
          local config = plugin.config
          if config.header_type == 'datadog' then
            config.header_type = 'preserve'
            log_warn_message('contains configuration opentelemetry.header_type == datadog',
                              'be overwritten with default value `preserve`',
                              dp_version, log_suffix)
            has_update = true
          end
        end
      end

      return has_update
    end
  },

  { 3004000000, --[[ 3.4.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local entity_names = {
        "plugins"
      }

      local has_update
      local updated_entities = {}

      for _, name in ipairs(entity_names) do
        for i, config_entity in ipairs(config_table[name] or {}) do
          -- Deactivate consumer_group-based plugins
          -- This step is crucial because older data planes lack the understanding of consumer-group-specific scope.
          -- Following the traditional method of "removing a field" could potentially disrupt the plugin's scope,
          -- subsequently leading to inconsistent and unpredictable user experiences.
          local consumer_group_scope = config_entity["consumer_group"]
          if consumer_group_scope ~= cjson.null and consumer_group_scope ~= nil then
            table.remove(config_table[name], i)

            has_update = true

            if not updated_entities[name] then
              log_warn_message("contains configuration '" .. name .. ".consumer_group'",
                               "the entire plugin will be disabled on this dataplane node",
                               dp_version,
                               log_suffix)

              updated_entities[name] = true
            end
          end
        end
      end

      -- remove ttl related parameters from vault configurations
      for _, vault in ipairs(config_table.vaults or {}) do
        local name = vault.name
        -- todo: once we do azure vault, we'll likely want to do the below in a better way, like
        -- with blacklisting env instead.
        if name == "aws" or name == "gcp" or name == "hcv" then
          for _, parameter in ipairs({ "ttl", "neg_ttl", "resurrect_ttl" }) do
            if vault.config[parameter] then
              vault.config[parameter] = nil
              has_update = true
            end
          end
        end
      end

      for _, plugin in ipairs(config_table.plugins or {}) do
        if plugin.name == 'opentelemetry' or plugin.name == 'zipkin' then
          local config = plugin.config
          if config.header_type == 'aws' then
            config.header_type = 'preserve'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' header_type == aws',
                             'overwritten with default value `preserve`',
                             dp_version, log_suffix)
            has_update = true
          end
        end

        if plugin.name == 'zipkin' then
          local config = plugin.config
          if config.default_header_type == 'aws' then
            config.default_header_type = 'b3'
            log_warn_message('configures ' .. plugin.name .. ' plugin with:' ..
                             ' default_header_type == aws',
                             'overwritten with default value `b3`',
                             dp_version, log_suffix)
            has_update = true
          end
        end
      end

      return has_update
    end
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      -- Support legacy queueing parameters for plugins that used queues prior to 3.3.  `retry_count` has been
      -- completely removed, so we always supply the default of 10 as that provides the same behavior as with a
      -- pre 3.3 CP.  The other queueing related legacy parameters can be determined from the new queue
      -- configuration table.
      for _, plugin in ipairs(config_table.plugins or {}) do
        local config = plugin.config

        if plugin.name == 'statsd' or plugin.name == 'datadog' then
          if type(config.retry_count) ~= "number" then
            config.retry_count = 10
            has_update = true
          end

          if type(config.queue_size) ~= "number" then
            if config.queue and type(config.queue.max_batch_size) == "number" then
              config.queue_size = config.queue.max_batch_size
              has_update = true

            else
              config.queue_size = 1
              has_update = true
            end
          end

          if type(config.flush_timeout) ~= "number" then
            if config.queue and type(config.queue.max_coalescing_delay) == "number" then
              config.flush_timeout = config.queue.max_coalescing_delay
              has_update = true

            else
              config.flush_timeout = 2
              has_update = true
            end
          end

        elseif plugin.name == 'opentelemetry' then

          if type(config.batch_span_count) ~= "number" then
            if config.queue and type(config.queue.max_batch_size) == "number" then
              config.batch_span_count = config.queue.max_batch_size
              has_update = true

            else
              config.batch_span_count = 200
              has_update = true
            end
          end

          if type(config.batch_flush_delay) ~= "number" then
            if config.queue and type(config.queue.max_coalescing_delay) == "number" then
              config.batch_flush_delay = config.queue.max_coalescing_delay
              has_update = true

            else
              config.batch_flush_delay = 3
              has_update = true
            end
          end
        end -- if plugin.name
      end   -- for

      return has_update
    end,
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local has_update

      for _, config_entity in ipairs(config_table.vaults or {}) do
        if config_entity.name == "env" and type(config_entity.config) == "table" then
          local config = config_entity.config
          local prefix = config.prefix

          if type(prefix) == "string" then
            local new_prefix = prefix:gsub("-", "_")
            if new_prefix ~= prefix then
              config.prefix = new_prefix
              has_update = true
            end
          end
        end
      end   -- for

      return has_update
    end,
  },

  { 3003000000, --[[ 3.3.0.0 ]]
    function(config_table, dp_version, log_suffix)
      -- remove updated_at field for core entities ca_certificates, certificates, consumers,
      -- targets, upstreams, plugins, workspaces, clustering_data_planes and snis
      local entity_names = {
        "ca_certificates", "certificates", "consumers", "targets", "upstreams",
        "plugins", "workspaces", "snis",
        -- XXX EE
        'consumer_group_consumers', 'consumer_group_plugins',
        'consumer_groups', 'credentials', 'event_hooks', 'keyring_meta', 'parameters',
        -- XXX EE
        }

      local has_update
      local updated_entities = {}

      for _, name in ipairs(entity_names) do
        for _, config_entity in ipairs(config_table[name] or {}) do
          if config_entity["updated_at"] then

            config_entity["updated_at"] = nil

            has_update = true

            if not updated_entities[name] then
              log_warn_message("contains configuration '" .. name .. ".updated_at'",
                               "be removed",
                               dp_version,
                               log_suffix)

              updated_entities[name] = true
            end
          end
        end
      end

      return has_update
    end
  },

  -- XXX EE
  { 3002000000, --[[ 3.2.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local config_plugins = config_table["plugins"]
      if not config_plugins then
        return nil
      end

      local has_update
      for i = #config_plugins, 1, -1 do
        local plugin = config_plugins[i]
        if plugin.name == "opentelemetry" and (plugin.service ~= null or plugin.route ~= null) then
          ngx_log(ngx_WARN, _log_prefix, "the plugin '", plugin.name,
                  "' is not supported to be configured with routes/serivces" ..
                  " on old dataplanes and will be removed.")

          table_remove(config_plugins, i)
          has_update = true
        end
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local config_services = config_table["services"]
      if not config_services  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_services) do
        if t["protocol"] == "tls" then
          if t["client_certificate"] or t["tls_verify"] or
             t["tls_verify_depth"]   or t["ca_certificates"]
          then

            t["client_certificate"] = nil
            t["tls_verify"] = nil
            t["tls_verify_depth"] = nil
            t["ca_certificates"] = nil

            has_update = true
          end
        end
      end

      if has_update then
        log_warn_message("tls protocol service contains configuration 'service.client_certificate'" ..
                         "or 'service.tls_verify' or 'service.tls_verify_depth' or 'service.ca_certificates'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local config_upstreams = config_table["upstreams"]
      if not config_upstreams  then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t["algorithm"] == "latency" then
          t["algorithm"] = "round-robin"
          has_update = true
        end
      end

      if has_update then
        log_warn_message("configuration 'upstream.algorithm' contains 'latency' option",
                         "fall back to 'round-robin'",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3002000000, --[[ 3.2.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local config_plugins = config_table["plugins"]
      if not config_plugins then
        return nil
      end

      local has_update
      for _, plugin in ipairs(config_plugins) do
        if plugin["instance_name"] ~= nil then
          plugin["instance_name"] = nil
          has_update = true
        end
      end

      if has_update then
        log_warn_message("contains configuration 'plugin.instance_name'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },

  { 3001000000, --[[ 3.1.0.0 ]]
    function(config_table, dp_version, log_suffix)
      local config_upstreams = config_table["upstreams"]
      if not config_upstreams then
        return nil
      end

      local has_update
      for _, t in ipairs(config_upstreams) do
        if t["use_srv_name"] ~= nil then
          t["use_srv_name"] = nil
          has_update = true
        end
      end

      if has_update then
        log_warn_message("contains configuration 'upstream.use_srv_name'",
                         "be removed",
                         dp_version,
                         log_suffix)
      end

      return has_update
    end
  },
}


return compatible_checkers
