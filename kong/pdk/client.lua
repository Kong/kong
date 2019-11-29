--- Client information module
-- A set of functions to retrieve information about the client connecting to
-- Kong in the context of a given request.
--
-- See also:
-- [nginx.org/en/docs/http/ngx_http_realip_module.html](http://nginx.org/en/docs/http/ngx_http_realip_module.html)
-- @module kong.client


local utils = require "kong.tools.utils"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local tonumber = tonumber
local check_phase = phase_checker.check
local check_not_phase = phase_checker.check_not


local PHASES = phase_checker.phases
local AUTH_AND_LATER = phase_checker.new(PHASES.access,
                                         PHASES.header_filter,
                                         PHASES.body_filter,
                                         PHASES.log)
local TABLE_OR_NIL = { ["table"] = true, ["nil"] = true }


local function new(self)
  local _CLIENT = {}


  ---
  -- Returns the remote address of the client making the request. This will
  -- **always** return the address of the client directly connecting to Kong.
  -- That is, in cases when a load balancer is in front of Kong, this function
  -- will return the load balancer's address, and **not** that of the
  -- downstream client.
  --
  -- @function kong.client.get_ip
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn string ip The remote address of the client making the request
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://example.com:1234/v1/movies
  -- kong.client.get_ip() -- "10.0.0.1"
  function _CLIENT.get_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  ---
  -- Returns the remote address of the client making the request. Unlike
  -- `kong.client.get_ip`, this function will consider forwarded addresses in
  -- cases when a load balancer is in front of Kong. Whether this function
  -- returns a forwarded address or not depends on several Kong configuration
  -- parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  --
  -- @function kong.client.get_forwarded_ip
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn string ip The remote address of the client making the request,
  -- considering forwarded addresses
  --
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://username:password@example.com:1234/v1/movies
  --
  -- kong.request.get_forwarded_ip() -- "127.0.0.1"
  --
  -- -- Note: assuming that 10.0.0.1 is one of the trusted IPs, and that
  -- -- the load balancer adds the right headers matching with the configuration
  -- -- of `real_ip_header`, e.g. `proxy_protocol`.
  function _CLIENT.get_forwarded_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.remote_addr
  end


  ---
  -- Returns the remote port of the client making the request. This will
  -- **always** return the port of the client directly connecting to Kong. That
  -- is, in cases when a load balancer is in front of Kong, this function will
  -- return load balancer's port, and **not** that of the downstream client.
  -- @function kong.client.get_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn number The remote client port
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_port() -- 30000
  function _CLIENT.get_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  ---
  -- Returns the remote port of the client making the request. Unlike
  -- `kong.client.get_port`, this function will consider forwarded ports in cases
  -- when a load balancer is in front of Kong. Whether this function returns a
  -- forwarded port or not depends on several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  -- @function kong.client.get_forwarded_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn number The remote client port, considering forwarded ports
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_forwarded_port() -- 40000
  --
  -- -- Note: assuming that [balancer] is one of the trusted IPs, and that
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
  -- @phases access, header_filter, body_filter, log
  -- @return the authenticated credential
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
  -- Returns the consumer from the datastore (or cache).
  -- Will look up the consumer by id, and optionally will do a second search by name.
  -- @function kong.client.load_consumer
  -- @phases access, header_filter, body_filter, log
  -- @tparam string consumer_id The consumer id to look up.
  -- @tparam [opt] search_by_username boolean. If truthy,
  -- then if the consumer was not found by id,
  -- then a second search by username will be performed
  -- @treturn table|nil consumer entity or nil
  -- @treturn nil|err nil if success, or error message if failure
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
      local result, err = kong.db.consumers:select { id = consumer_id }

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
  -- @phases access, header_filter, body_filter, log
  -- @treturn table the authenticated consumer entity
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
  -- Sets the authenticated consumer and/or credential for the current request.
  -- While both `consumer` and `credential` can be `nil`, it is required
  -- that at least one of them exists. Otherwise this function will throw an
  -- error.
  -- @function kong.client.authenticate
  -- @phases access
  -- @tparam table|nil consumer The consumer to set. Note: if no
  -- value is provided, then any existing value will be cleared!
  -- @tparam table|nil credential The credential to set. Note: if
  -- no value is provided, then any existing value will be cleared!
  -- @usage
  -- -- assuming `credential` and `consumer` have been set by some authentication code
  -- kong.client.authenticate(consumer, credentials)
  function _CLIENT.authenticate(consumer, credential)
    check_phase(PHASES.access)

    if not TABLE_OR_NIL[type(consumer)] then
      error("consumer must be a table or nil", 2)
    elseif not TABLE_OR_NIL[type(credential)] then
      error("credential must be a table or nil", 2)
    elseif credential == nil and consumer == nil then
      error("either credential or consumer must be provided", 2)
    end

    local ctx = ngx.ctx
    ctx.authenticated_consumer = consumer
    ctx.authenticated_credential = credential
  end


  ---
  -- Returns the protocol matched by the current route (`"http"`, `"https"`, `"tcp"` or
  -- `"tls"`), or `nil`, if no route has been matched, which can happen when dealing with
  -- erroneous requests.
  -- @function kong.client.get_protocol
  -- @phases access, header_filter, body_filter, log
  -- @tparam [opt] allow_terminated boolean. If set, the `X-Forwarded-Proto` header will be checked when checking for https
  -- @treturn string|nil `"http"`, `"https"`, `"tcp"`, `"tls"` or `nil`
  -- @treturn nil|err nil if success, or error message if failure
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
