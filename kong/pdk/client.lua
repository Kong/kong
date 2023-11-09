-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Client information module.
--
-- A set of functions to retrieve information about the client connecting to
-- Kong in the context of a given request.
--
-- See also:
-- [nginx.org/en/docs/http/ngx_http_realip_module.html](http://nginx.org/en/docs/http/ngx_http_realip_module.html)
-- @module kong.client


local utils = require "kong.tools.utils"
local phase_checker = require "kong.pdk.private.phases"
local consumer_group_helpers = require "kong.enterprise_edition.consumer_groups_helpers"
local get_groups_by_consumer = consumer_group_helpers.get_groups_by_consumer


local ngx = ngx
local tonumber = tonumber
local check_phase = phase_checker.check
local check_not_phase = phase_checker.check_not


local PHASES = phase_checker.phases
local ACCESS_AND_WS_HANDSHAKE = phase_checker.new(PHASES.access,
                                                  PHASES.ws_handshake)

local AUTH_AND_LATER = phase_checker.new(PHASES.access,
                                         PHASES.header_filter,
                                         PHASES.response,
                                         PHASES.body_filter,
                                         PHASES.log,
                                         PHASES.ws_handshake,
                                         PHASES.ws_proxy,
                                         PHASES.ws_close)

local TABLE_OR_NIL = { ["table"] = true, ["nil"] = true }
local STRING_OR_NIL = { ["string"] = true, ["nil"] = true }

local stream_subsystem = ngx.config.subsystem == "stream"


local function new(self)
  local _CLIENT = {}


  ---
  -- Returns the remote address of the client making the request. This module
  -- **always** returns the address of the client directly connecting to Kong.
  -- That is, in cases when a load balancer is in front of Kong, this function
  -- returns the load balancer's address, and **not** that of the
  -- downstream client.
  --
  -- @function kong.client.get_ip
  -- @phases certificate, rewrite, access, header_filter, response, body_filter, log
  -- @treturn string The remote IP address of the client making the request.
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://example.com:1234/v1/movies
  -- kong.client.get_ip() -- "10.0.0.1"
  function _CLIENT.get_ip()
    check_not_phase(PHASES.init_worker)

    -- when proxying TLS request in second layer or doing TLS passthrough
    -- realip_remote_addr is always the previous layer of nginx thus always unix:
    if stream_subsystem and
        (ngx.var.kong_tls_passthrough_block == "1" or ngx.var.ssl_protocol) then
      return ngx.var.remote_addr
    end

    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  ---
  -- Returns the remote address of the client making the request. Unlike
  -- `kong.client.get_ip`, this function will consider forwarded addresses in
  -- cases when a load balancer is in front of Kong. Whether this function
  -- returns a forwarded address or not depends on several Kong configuration
  -- parameters:
  --
  -- * [trusted\_ips](https://docs.konghq.com/gateway/latest/reference/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://docs.konghq.com/gateway/latest/reference/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://docs.konghq.com/gateway/latest/reference/configuration/#real_ip_recursive)
  --
  -- @function kong.client.get_forwarded_ip
  -- @phases certificate, rewrite, access, header_filter, response, body_filter, log
  -- @treturn string The remote IP address of the client making the request,
  -- considering forwarded addresses.
  --
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://username:password@example.com:1234/v1/movies
  --
  -- kong.client.get_forwarded_ip() -- "127.0.0.1"
  --
  -- -- Note: This example assumes that 10.0.0.1 is one of the trusted IPs, and that
  -- -- the load balancer adds the right headers matching with the configuration
  -- -- of `real_ip_header`, e.g. `proxy_protocol`.
  function _CLIENT.get_forwarded_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.remote_addr
  end


  ---
  -- Returns the remote port of the client making the request. This
  -- **always** returns the port of the client directly connecting to Kong. That
  -- is, in cases when a load balancer is in front of Kong, this function
  -- returns the load balancer's port, and **not** that of the downstream client.
  -- @function kong.client.get_port
  -- @phases certificate, rewrite, access, header_filter, response, body_filter, log
  -- @treturn number The remote client port.
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_port() -- 30000
  function _CLIENT.get_port()
    check_not_phase(PHASES.init_worker)

    -- when proxying TLS request in second layer or doing TLS passthrough
    -- realip_remote_addr is always the previous layer of nginx thus always unix:
    if stream_subsystem and
        (ngx.var.kong_tls_passthrough_block == "1" or ngx.var.ssl_protocol) then
      return tonumber(ngx.var.remote_port)
    end

    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  ---
  -- Returns the remote port of the client making the request. Unlike
  -- `kong.client.get_port`, this function will consider forwarded ports in cases
  -- when a load balancer is in front of Kong. Whether this function returns a
  -- forwarded port or not depends on several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://docs.konghq.com/gateway/latest/reference/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://docs.konghq.com/gateway/latest/reference/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://docs.konghq.com/gateway/latest/reference/configuration/#real_ip_recursive)
  -- @function kong.client.get_forwarded_port
  -- @phases certificate, rewrite, access, header_filter, response, body_filter, log
  -- @treturn number The remote client port, considering forwarded ports.
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_forwarded_port() -- 40000
  --
  -- -- Note: This example assumes that [balancer] is one of the trusted IPs, and that
  -- -- the load balancer adds the right headers matching with the configuration
  -- -- of `real_ip_header`, e.g. `proxy_protocol`.
  function _CLIENT.get_forwarded_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.remote_port)
  end


  ---
  -- Returns the credentials of the currently authenticated consumer.
  -- If not set yet, it returns `nil`.
  -- @function kong.client.get_credential
  -- @phases access, header_filter, response, body_filter, log
  -- @treturn string The authenticated credential.
  -- @usage
  -- local credential = kong.client.get_credential()
  -- if credential then
  --   consumer_id = credential.consumer_id
  -- else
  --   -- request not authenticated yet
  -- end
  function _CLIENT.get_credential()
    check_phase(AUTH_AND_LATER)

    return ngx.ctx.authenticated_credential
  end


  ---
  -- Returns the consumer from the datastore.
  -- Looks up the consumer by ID, and can optionally do a second search by name.
  -- @function kong.client.load_consumer
  -- @phases access, header_filter, response, body_filter, log
  -- @tparam string consumer_id The consumer ID to look up.
  -- @tparam[opt] boolean search_by_username If truthy,
  -- and if the consumer is not found by ID,
  -- then a second search by username will be performed.
  -- @treturn table|nil Consumer entity or `nil`.
  -- @treturn nil|err `nil` if successful, or an error message if it fails.
  -- @usage
  -- local consumer_id = "john_doe"
  -- local consumer = kong.client.load_consumer(consumer_id, true)
  function _CLIENT.load_consumer(consumer_id, search_by_username)
    check_phase(AUTH_AND_LATER)

    if not consumer_id or type(consumer_id) ~= "string" then
      error("consumer_id must be a string", 2)
    end

    if not utils.is_valid_uuid(consumer_id) and not search_by_username then
      error("cannot load a consumer with an id that is not a uuid", 2)
    end

    if utils.is_valid_uuid(consumer_id) then
      local result, err = kong.db.consumers:select({ id = consumer_id })

      if result then
        return result
      end

      if err then
        return nil, err
      end
    end

    -- no error and if search_by_username, look up by username
    if search_by_username then
      return kong.db.consumers:select_by_username(consumer_id)
    end

  end


  ---
  -- Returns the `consumer` entity of the currently authenticated consumer.
  -- If not set yet, it returns `nil`.
  -- @function kong.client.get_consumer
  -- @phases access, header_filter, response, body_filter, log
  -- @treturn table The authenticated consumer entity.
  -- @usage
  -- local consumer = kong.client.get_consumer()
  -- if consumer then
  --   consumer_id = consumer.id
  -- else
  --   -- request not authenticated yet, or a credential
  --   -- without a consumer (external auth)
  -- end
  function _CLIENT.get_consumer()
    check_phase(AUTH_AND_LATER)

    return ngx.ctx.authenticated_consumer
  end


  ---
  -- Sets the authenticated consumer and/or credential as well
  -- as the authenticated consumer-group for the current request.
  -- While both `consumer` and `credential` can be `nil`,
  -- at least one of them must exist. Otherwise, this function will throw an
  -- error.
  -- @function kong.client.authenticate
  -- @phases access
  -- @tparam table|nil consumer The consumer to set. If no
  -- value is provided, then any existing value will be cleared.
  -- @tparam table|nil credential The credential to set. If
  -- no value is provided, then any existing value will be cleared.
  -- @usage
  -- -- assuming `credential` and `consumer` have been set by some authentication code
  -- kong.client.authenticate(consumer, credentials)
  function _CLIENT.authenticate(consumer, credential)
    check_phase(ACCESS_AND_WS_HANDSHAKE)

    if not TABLE_OR_NIL[type(consumer)] then
      error("consumer must be a table or nil", 2)
    elseif not TABLE_OR_NIL[type(credential)] then
      error("credential must be a table or nil", 2)
    elseif credential == nil and consumer == nil then
      error("either credential or consumer must be provided", 2)
    end

    local ctx = ngx.ctx
    -- When authenticating, we assign `authenticated_consumer_group`
    -- based on `consumer` affiliation.
    self.client.authenticate_consumer_group_by_consumer_id(consumer and consumer.id)
    ctx.authenticated_consumer = consumer
    ctx.authenticated_credential = credential
  end

  ---
  -- Explicitly sets the authenticated consumer group for the current request.
  -- Throws an error if the `group` is neither a table nor `nil`.
  -- @function _CLIENT.set_authenticated_consumer_groups
  -- @phases auth_and_later
  -- @tparam table|nil group The consumer group to set. If no
  -- value is provided, then any existing value will be cleared.
  -- this value should be a table of tables where each group is an
  -- table with metadata of the group like its `id` and `name`.
  -- @usage
  -- -- assuming `group` is provided by some code
  -- _CLIENT.set_authenticated_consumer_groups(group)
  function _CLIENT.set_authenticated_consumer_groups(groups)
    -- This is the counterpart for `authenticate_consumer_group_by_consumer_id`
    -- This method allows to explicitly set a group. This allows a plugin to set groups
    -- based on any other affiliations rather than a consumer <-> consumer_group mapping.
    check_phase(AUTH_AND_LATER)

    if not TABLE_OR_NIL[type(groups)] then
      error("consumer group must be a table or nil", 2)
    end

    -- FIXME: add checks to verify that all groups have a `id` and a `name` attribute

    -- This is a preliminary measure to ensure deterministic behavior when dealing with multiple consumer-groups
    -- per consumer. For now, we sort by consumer-group name but this is subject to change in future releases.
    table.sort(groups or {}, function (a, b)
      return a.name < b.name
    end)

    ngx.ctx.authenticated_consumer_groups = groups
  end

  ---
  -- This function is deprecated in favor of `set_authenticated_consumer_groups`.
  -- Explicitly sets the authenticated consumer group for the current request.
  -- Throws an error if the `group` is neither a table nor `nil`.
  -- @function _CLIENT.set_authenticated_consumer_group
  -- @phases auth_and_later
  -- @tparam table|nil group The consumer group to set. If no
  -- value is provided, then any existing value will be cleared.
  -- this value should be a table with metadata of the group like its `id` and `name`.
  -- @usage
  -- -- assuming `group` is provided by some code
  -- _CLIENT.set_authenticated_consumer_group(group)
  function _CLIENT.set_authenticated_consumer_group(group)
    -- This is the counterpart for `authenticate_consumer_group_by_consumer_id`
    -- This method allows to explicitly set consumer groups. This allows a plugin to set groups
    -- based on any other affiliations rather than a consumer <-> consumer_group mapping.
    check_phase(AUTH_AND_LATER)
    self.log.deprecation("this function is deprecated in favor of `set_authenticated_consumer_groups`." ..
      "Note that setting a consumer_group using this function will not affect the plugin execution logic.",
      { after = "3.4.0.0", removal = "3.5.0.0" })

    if not TABLE_OR_NIL[type(group)] then
      error("consumer group must be a table or nil", 2)
    end

    ngx.ctx.authenticated_consumer_group = group
  end

  ---
  -- Retrieves the authenticated consumer groups for the current request.
  -- @function _CLIENT.get_consumer_groups
  -- @phases auth_and_later
  -- @treturn table|nil The authenticated consumer groups. Returns `nil` if no
  -- consumer groups has been authenticated for the current request.
  -- @usage
  -- local groups = _CLIENT.get_consumer_groups()
  function _CLIENT.get_consumer_groups()
    check_phase(AUTH_AND_LATER)

    return ngx.ctx.authenticated_consumer_groups
  end

  ---
  -- This function is deprecated in favor of `get_consumer_groups`.
  -- Retrieves the authenticated consumer group for the current request.
  -- @function _CLIENT.get_consumer_group
  -- @phases auth_and_later
  -- @treturn table|nil The authenticated consumer group. Returns `nil` if no
  -- consumer group has been authenticated for the current request.
  -- @usage
  -- local group = _CLIENT.get_consumer_group()
  function _CLIENT.get_consumer_group()
    check_phase(AUTH_AND_LATER)
    self.log.deprecation("this function is deprecated in favor of `get_consumer_groups`", {after = "3.4.0.0", removal = "3.5.0.0"})

    return ngx.ctx.authenticated_consumer_group
  end

--- Sets the consumer group for the current request based on the provided consumer id.
-- If the consumer_id is neither a string nor nil, it throws an error.
-- If the consumer group has already been authenticated, it doesn't override the group.
-- The function performs a redis-SCAN-like lookup using a subset of the cache_key.
-- The consumer_group_mapping is sorted by group name for deterministic behavior,
-- but this might be changed in future releases.
--
-- @function _CLIENT.authenticate_consumer_group_by_consumer_id
-- @phases access
-- @tparam string|nil consumer_id The consumer id to use for setting the consumer group.
-- If no value is provided, the current consumer group is not changed.
-- @usage
-- -- assuming `consumer_id` is provided by some code
-- _CLIENT.authenticate_consumer_group_by_consumer_id(consumer_id)
  function _CLIENT.authenticate_consumer_group_by_consumer_id(consumer_id)
    check_phase(ACCESS_AND_WS_HANDSHAKE)

    if not STRING_OR_NIL[type(consumer_id)] then
      error("consumer_id must be a sting or nil", 2)
    end

    local ctx = ngx.ctx
    -- do not override any authenticated group when alreaedy set. a previous plugin
    -- might have set this explicity.
    if ctx.authenticated_consumer_group or ctx.authenticated_consumer_groups then
     return nil
    end

    -- Use a subset of the `cache_key` like `"":consumer-x` to do a `redis-SCAN` like lookup.
    local cache_key = kong.db.consumer_group_consumers:cache_key("", consumer_id)
    local consumer_group_mapping, err = kong.cache:get(cache_key, nil, get_groups_by_consumer, consumer_id)

    if not err and consumer_group_mapping then
      self.client.set_authenticated_consumer_groups(consumer_group_mapping)
    end
  end

  ---
  -- Returns the protocol matched by the current route (`"http"`, `"https"`, `"tcp"` or
  -- `"tls"`), or `nil`, if no route has been matched, which can happen when dealing with
  -- erroneous requests.
  -- @function kong.client.get_protocol
  -- @phases access, header_filter, response, body_filter, log
  -- @tparam[opt] boolean allow_terminated If set, the `X-Forwarded-Proto` header is checked when checking for HTTPS.
  -- @treturn string|nil Can be one of `"http"`, `"https"`, `"tcp"`, `"tls"` or `nil`.
  -- @treturn nil|err `nil` if successful, or an error message if it fails.
  -- @usage
  -- kong.client.get_protocol() -- "http"
  function _CLIENT.get_protocol(allow_terminated)
    check_phase(AUTH_AND_LATER)

    local route = ngx.ctx.route
    if not route then
      return nil, "No active route found"
    end

    local protocols = route.protocols
    if #protocols == 1 then
      return protocols[1]
    end

    if ngx.config.subsystem == "http" then
      local is_trusted = self.ip.is_trusted(self.client.get_ip())
      local is_https, err = utils.check_https(is_trusted, allow_terminated)
      if err then
        return nil, err
      end

      return is_https and "https" or "http"
    end
    -- else subsystem is stream

    local balancer_data = ngx.ctx.balancer_data
    local is_tls = balancer_data and balancer_data.scheme == "tls"

    return is_tls and "tls" or "tcp"
  end


  return _CLIENT
end


return {
  new = new,
}
