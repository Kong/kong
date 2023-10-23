-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ssl_fixtures = require "spec.fixtures.ssl"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


local fmt = string.format


local Blueprint   = {}
Blueprint.__index = Blueprint


-- TODO: port this back to OSS since it should be useful there too
function Blueprint:defaults(defaults)
  self._defaults = defaults
end

function Blueprint:build(overrides)
  overrides = overrides or {}
  if self._defaults then
    overrides = utils.cycle_aware_deep_merge(self._defaults, overrides)
  end

  return utils.cycle_aware_deep_merge(self.build_function(overrides), overrides)
end


function Blueprint:insert(overrides, options)
  local entity, err = self.dao:insert(self:build(overrides), options)
  if err then
    error(err, 2)
  end
  return entity
end


-- insert blueprint in workspace specified by `ws`
function Blueprint:insert_ws(overrides, workspace)
  local old_workspace = ngx.ctx.workspace

  ngx.ctx.workspace = workspace.id
  local entity = self:insert(overrides)
  ngx.ctx.workspace = old_workspace

  return entity
end


function Blueprint:remove(overrides, options)
  local entity, err = self.dao:remove({ id = overrides.id }, options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:update(id, overrides, options)
  local entity, err = self.dao:update(id, overrides, options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:upsert(id, overrides, options)
  local entity, err = self.dao:upsert(id, overrides, options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:insert_n(n, overrides, options)
  local res = {}
  for i=1,n do
    res[i] = self:insert(overrides, options)
  end
  return res
end

function Blueprint:truncate()
  local _, err = self.dao:truncate()
  if err then
    error(err, 2)
  end
  return true
end

local function new_blueprint(dao, build_function)
  return setmetatable({
    dao = dao,
    build_function = build_function,
  }, Blueprint)
end


local Sequence = {}
Sequence.__index = Sequence


function Sequence:next()
  return fmt(self.sequence_string, self:gen())
end

function Sequence:gen()
  self.count = self.count + 1
  return self.count
end

local function new_sequence(sequence_string, gen)
  return setmetatable({
    count           = 0,
    sequence_string = sequence_string,
    gen             = gen,
  }, Sequence)
end


local _M = {}


function _M.new(db)
  local res = {}

  -- prepare Sequences and random values
  local acl_group_seq = new_sequence("acl-group-%d")
  local consumer_custom_id_seq = new_sequence("consumer-id-%s")
  local consumer_username_seq = new_sequence("consumer-username-%s", utils.uuid)
  local consumer_group_name_seq = new_sequence("consumer-group-name-%d")
  local developer_email_seq = new_sequence("dev-%d@example.com")
  local file_name_seq = new_sequence("file-path-%d.txt")
  local group_name_seq = new_sequence("group-name-%d")
  local hmac_username_seq = new_sequence("hmac-username-%d")
  local jwt_key_seq = new_sequence("jwt-key-%d")
  local key_sets_seq = new_sequence("key-sets-%d")
  local keys_seq = new_sequence("keys-%d")
  local keyauth_key_seq = new_sequence("keyauth-key-%d")
  local named_service_name_seq = new_sequence("service-name-%d")
  local named_service_host_seq = new_sequence("service-host-%d.test")
  local named_route_name_seq = new_sequence("route-name-%d")
  local named_route_host_seq = new_sequence("route-host-%d.test")
  local oauth_code_seq = new_sequence("oauth-code-%d")
  local plugin_name_seq = new_sequence("custom-plugin-%d")
  local rbac_role_endpoint_seq = new_sequence("/rbac-role-endpoint-%d")
  local rbac_user_name_seq = new_sequence("rbac-user-%d")
  local rbac_roles_seq = new_sequence("rbac-role-%d")
  local sni_seq = new_sequence("sni-%s", utils.uuid)
  local upstream_name_seq = new_sequence("upstream-%s", utils.uuid)
  local workspace_name_seq = new_sequence("workspace-name-%d")

  local random_ip = tostring(math.random(1, 255)) .. "." ..
    tostring(math.random(1, 255)) .. "." ..
    tostring(math.random(1, 255)) .. "." ..
    tostring(math.random(1, 255))
  local random_target = random_ip .. ":" .. tostring(math.random(1, 65535))

  res.snis = new_blueprint(db.snis, function(overrides)
    return {
      name        = overrides.name or sni_seq:next(),
      certificate = overrides.certificate or res.certificates:insert(),
    }
  end)

  res.certificates = new_blueprint(db.certificates, function()
    return {
      cert = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    }
  end)

  res.ca_certificates = new_blueprint(db.ca_certificates, function()
    return {
      cert = ssl_fixtures.cert_ca,
    }
  end)

  res.upstreams = new_blueprint(db.upstreams, function(overrides)
    return {
      name      = overrides.name or upstream_name_seq:next(),
      slots     = overrides.slots or 100,
      host_header = overrides.host_header,
    }
  end)

  res.consumers = new_blueprint(db.consumers, function()
    return {
      custom_id = consumer_custom_id_seq:next(),
      username  = consumer_username_seq:next(),
    }
  end)

  res.developers = new_blueprint(db.developers, function()
    return {
      email = developer_email_seq:next(),
    }
  end)

  res.targets = new_blueprint(db.targets, function(overrides)
    return {
      weight = overrides.weight or 10,
      upstream = overrides.upstream or res.upstreams:insert(),
      target = overrides.target or random_target,
    }
  end)

  res.plugins = new_blueprint(db.plugins, function(overrides)
    -- we currently don't know which plugin is enabled
    return overrides or {}
  end)

  res.routes = new_blueprint(db.routes, function(overrides)
    local service = overrides.service
    local protocols = overrides.protocols

    local route = {
      service = service,
    }

    if overrides.no_service then
      service = nil
      overrides.no_service = nil
      return {
        service = service,
      }
    end


    if type(service) == "table" then
      -- set route.protocols from service
      if service.protocol == "ws" or
         service.protocol == "wss" and
        not protocols
      then
        route.protocols = { service.protocol }
      end

    else
      service = {}

      -- set service.protocol from route.protocols
      if type(protocols) == "table" then
        for _, proto in ipairs(protocols) do
          if proto == "ws" or proto == "wss" then
            service.protocol = proto
            break
          end
        end
      end

      service = res.services:insert(service)

      -- reverse: set route.protocols based on the inserted service, which
      -- may have inherited some defaults
      if protocols == nil and
         (service.protocol == "ws" or service.protocol == "wss")
      then
        route.protocols = { service.protocol }
      end

      route.service = service
    end

    return route
  end)

  res.services = new_blueprint(db.services, function(overrides)
    local service = {
      protocol = "http",
      host = "127.0.0.1",
      port = 15555,
    }

    service.protocol = overrides.protocol or service.protocol

    if service.protocol == "ws" then
      service.port = 3000

    elseif service.protocol == "wss" then
      service.port = 3001
    end

    return service
  end)

  res.vaults = new_blueprint(db.vaults, function(overrides)
    local vault = {
      name = "env",
      prefix = "env-1",
      description = "description",
    }

    vault.prefix = overrides.prefix or vault.prefix
    vault.description = overrides.description or vault.description

    return vault
  end)

  res.rbac_role_entities = new_blueprint(db.rbac_role_entities, function(overrides)
    return {
      role = overrides.role or res.rbac_roles:insert(),
      entity_id = overrides.entity_id or res.routes:insert().id,
      entity_type = overrides.entity_type or "route",
      actions = overrides.actions or 15,
    }
  end)

  res.rbac_role_endpoints = new_blueprint(db.rbac_role_endpoints, function (overrides)
    return {
      role = overrides.role or res.rbac_roles:insert(),
      endpoint = overrides.endpoint or rbac_role_endpoint_seq:next(),
      actions = overrides.action or 15,
    }
  end)

  res.parameters = new_blueprint(db.parameters, function ()
    return {
      key = utils.uuid(),
      value = utils.uuid(),
    }
  end)

  res.login_attempts = new_blueprint(db.login_attempts, function (overrides)
    return {
      consumer = overrides.consumer or res.consumers:insert(),
      attempts = { [random_ip] = math.random(1, 255) },
    }
  end)

  res.legacy_files = new_blueprint(db.legacy_files, function (overrides)
    return {
      name = overrides.name or utils.uuid(),
      type = overrides.type or "page",
      contents = overrides.contents or utils.random_string(),
    }
  end)

  res.keyring_meta = new_blueprint(db.keyring_meta, function ()
    return {
      id = utils.uuid()
    }
  end)

  res.groups = new_blueprint(db.groups, function ()
    return {
      name = group_name_seq:next(),
    }
  end)

  res.group_rbac_roles = new_blueprint(db.group_rbac_roles, function (overrides)
    return {
      group = overrides.group or res.groups:insert(),
      rbac_role = overrides.rbac or res.rbac_roles:insert(),
      workspace = overrides.workspace or res.workspaces:insert(),
    }
  end)

  res.document_objects = new_blueprint(db.document_objects, function (overrides)
    return {
      service = overrides.service or res.services:insert(),
      path = overrides.path or res.files:insert().path,
    }
  end)

  res.files = new_blueprint(db.files, function ()
    return {
      path = file_name_seq:next(),
      contents = utils.random_string(),
    }
  end)

  res.event_hooks = new_blueprint(db.event_hooks, function (overrides)
    local HANDLER = {
      handler_name = "webhook",
      config = {
        url = "http://localhost/",
      }
    }
    local event_hook = {
      -- source = event_hook_source_seq:next(),
      source = overrides.source,
      handler = overrides.handler or HANDLER.handler_name,
      config = overrides.config or HANDLER.config,
    }
    return event_hook
  end)

  res.credentials = new_blueprint(db.credentials, function(overrides)
    local credential = {
      consumer = overrides.consumer or res.consumers:insert(),
      plugin = overrides.plugin_name or plugin_name_seq:next(),
      credential_data = cjson.encode({ [utils.random_string()] = utils.random_string() }),
    }
    return credential
  end)

  res.consumer_groups = new_blueprint(db.consumer_groups, function(overrides)
    return {
      name = overrides.name or consumer_group_name_seq:next(),
      id = overrides.id or utils.uuid()
    }
  end)

  res.consumer_group_plugins = new_blueprint(db.consumer_group_plugins, function(overrides)
    local consumer_group_plugins = {
      consumer_group = overrides.consumer_group or res.consumer_groups:insert(),
      name = "consumer-group-" .. utils.uuid(),
      config = {
        window_size = { math.random(1,100) },
        window_type = overrides.config and overrides.config.window_type or "fixed",
        limit = { math.random(1,100) },
      }
    }
    return consumer_group_plugins
  end)

  res.consumer_group_consumers = new_blueprint(db.consumer_group_consumers, function(overrides)
    return {
      consumer = overrides.consumer or res.consumers:insert(),
      consumer_group = overrides.consumer_group or res.consumer_groups:insert(),
    }
  end)

  res.clustering_data_planes = new_blueprint(db.clustering_data_planes, function()
    return {
      hostname = "dp.example.com",
      ip = "127.0.0.1",
      config_hash = "a9a166c59873245db8f1a747ba9a80a7",
    }
  end)

  res.named_services = new_blueprint(db.services, function()
    return {
      protocol = "http",
      name = named_service_name_seq:next(),
      host = named_service_host_seq:next(),
      port = 15555,
    }
  end)

  res.named_routes = new_blueprint(db.routes, function(overrides)
    return {
      name = named_route_name_seq:next(),
      hosts = { named_route_host_seq:next() },
      service = overrides.service or res.services:insert(),
    }
  end)

  res.acl_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "acl",
      config = {},
    }
  end)

  res.acls = new_blueprint(db.acls, function()
    return {
      group = acl_group_seq:next(),
    }
  end)

  res.cors_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "cors",
      config = {
        origins         = { "example.com" },
        methods         = { "GET" },
        headers         = { "origin", "type", "accepts"},
        exposed_headers = { "x-auth-token" },
        max_age         = 23,
        credentials     = true,
      }
    }
  end)

  res.loggly_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "loggly",
      config = {}, -- all fields have default values already
    }
  end)

  res.tcp_log_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "tcp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  res.udp_log_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  res.jwt_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "jwt",
      config = {},
    }
  end)

  res.jwt_secrets = new_blueprint(db.jwt_secrets, function()
    return {
      key       = jwt_key_seq:next(),
      secret    = "secret",
    }
  end)

  res.oauth2_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "oauth2",
      config = {
        scopes                    = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope           = true,
        provision_key             = "provision123",
        token_expiration          = 5,
        enable_implicit_grant     = true,
      }
    }
  end)

  res.oauth2_credentials = new_blueprint(db.oauth2_credentials, function()
    return {
      name          = "oauth2 credential",
      client_secret = "secret",
    }
  end)

  res.oauth2_authorization_codes = new_blueprint(db.oauth2_authorization_codes, function()
    return {
      code  = oauth_code_seq:next(),
      scope = "default",
    }
  end)

  res.oauth2_tokens = new_blueprint(db.oauth2_tokens, function()
    return {
      token_type = "bearer",
      expires_in = 1000000000,
      scope      = "default",
    }
  end)

  res.key_auth_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "key-auth",
      config = {},
    }
  end)

  res.keyauth_credentials = new_blueprint(db.keyauth_credentials, function()
    return {
      key = keyauth_key_seq:next(),
    }
  end)

  local keyauth_enc_key_seq = new_sequence("keyauth-enc-key-%d")
  res.keyauth_enc_credentials = new_blueprint(db.keyauth_enc_credentials, function()
    return {
      key = keyauth_enc_key_seq:next(),
    }
  end)

  res.keyauth_enc_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "key-auths-enc",
      config = {},
    }
  end)

  res.basicauth_credentials = new_blueprint(db.basicauth_credentials, function()
    return {}
  end)

  res.hmac_auth_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "hmac-auth",
      config = {},
    }
  end)

  res.hmacauth_credentials = new_blueprint(db.hmacauth_credentials, function()
    return {
      username = hmac_username_seq:next(),
      secret   = "secret",
    }
  end)

  res.rate_limiting_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "rate-limiting",
      config = {},
    }
  end)

  res.response_ratelimiting_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "response-ratelimiting",
      config = {},
    }
  end)

  res.datadog_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "datadog",
      config = {},
    }
  end)

  res.statsd_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "statsd",
      config = {},
    }
  end)

  res.workspaces = new_blueprint(db.workspaces, function()
    return {
      name = workspace_name_seq:next(),
    }
  end)

  res.rewriter_plugins = new_blueprint(db.plugins, function()
    return {
      name   = "rewriter",
      config = {},
    }
  end)

  res.rbac_users = new_blueprint(db.rbac_users, function()
    return {
      name = rbac_user_name_seq:next(),
      user_token = utils.uuid(),
    }
  end)

  res.rbac_roles = new_blueprint(db.rbac_roles, function()
    return {
      name = rbac_roles_seq:next(),
    }
  end)

  res.key_sets = new_blueprint(db.key_sets, function()
    return {
      name = key_sets_seq:next(),
    }
  end)

  res.keys = new_blueprint(db.keys, function()
    return {
      name = keys_seq:next(),
    }
  end)

  res.vaults = new_blueprint(db.vaults, function()
    return {}
  end)

  local filter_chains_seq = new_sequence("filter-chains-%d")
  res.filter_chains = new_blueprint(db.filter_chains, function()
    return {
      name = filter_chains_seq:next(),
    }
  end)

  return res
end


return _M
