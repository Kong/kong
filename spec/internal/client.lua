------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local pl_tablex = require("pl.tablex")
local luassert = require("luassert.assert")
local cjson = require("cjson.safe")
local http = require("resty.http")
local kong_table = require("kong.tools.table")
local uuid = require("kong.tools.uuid").uuid


local CONSTANTS = require("spec.internal.constants")
local conf = require("spec.internal.conf")
local shell = require("spec.internal.shell")
local misc = require("spec.internal.misc")
local asserts = require("spec.internal.asserts") -- luacheck: ignore


-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = setmetatable({}, { __index = http })
resty_http_proxy_mt.__index = resty_http_proxy_mt


--- Check if a request can be retried in the case of a closed connection
--
-- For now this is limited to "safe" methods as defined by:
-- https://datatracker.ietf.org/doc/html/rfc7231#section-4.2.1
--
-- XXX Since this strictly applies to closed connections, it might be okay to
-- open this up to include idempotent methods like PUT and DELETE if we do
-- some more testing first
local function can_reopen(method)
  method = string.upper(method or "GET")
  return method == "GET"
      or method == "HEAD"
      or method == "OPTIONS"
      or method == "TRACE"
end


--- http_client.
-- An http-client class to perform requests.
--
-- * Based on [lua-resty-http](https://github.com/pintsized/lua-resty-http) but
-- with some modifications
--
-- * Additional convenience methods will be injected for the following methods;
-- "get", "post", "put", "patch", "delete". Each of these methods comes with a
-- built-in assert. The signature of the functions is `client:get(path, opts)`.
--
-- * Body will be formatted according to the "Content-Type" header, see `http_client:send`.
--
-- * Query parameters will be added, see `http_client:send`.
--
-- @section http_client
-- @usage
-- -- example usage of the client
-- local client = helpers.proxy_client()
-- -- no need to check for `nil+err` since it is already wrapped in an assert
--
-- local opts = {
--   headers = {
--     ["My-Header"] = "my header value"
--   }
-- }
-- local result = client:get("/services/foo", opts)
-- -- the 'get' is wrapped in an assert, so again no need to check for `nil+err`


--- Send a http request.
-- Based on [lua-resty-http](https://github.com/pintsized/lua-resty-http).
--
-- * If `opts.body` is a table and "Content-Type" header contains
-- `application/json`, `www-form-urlencoded`, or `multipart/form-data`, then it
-- will automatically encode the body according to the content type.
--
-- * If `opts.query` is a table, a query string will be constructed from it and
-- appended to the request path (assuming none is already present).
--
-- * instead of this generic function there are also shortcut functions available
-- for every method, eg. `client:get`, `client:post`, etc. See `http_client`.
--
-- @function http_client:send
-- @param opts table with options. See [lua-resty-http](https://github.com/pintsized/lua-resty-http)
function resty_http_proxy_mt:send(opts, is_reopen)
  local encode_args = require("kong.tools.http").encode_args

  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type, content_type_name = misc.lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(opts.body) == "table"

  if string.find(content_type, "application/json") and t_body_table then
    opts.body = cjson.encode(opts.body)

  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = encode_args(opts.body, true, opts.no_array_indexes)

  elseif string.find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = opts.body
    local boundary = "8fd84e9444e3946c"
    local body = ""

    for k, v in pairs(form) do
      body = body .. "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. k .. "\"\r\n\r\n" .. tostring(v) .. "\r\n"
    end

    if body ~= "" then
      body = body .. "--" .. boundary .. "--\r\n"
    end

    local clength = misc.lookup(headers, "content-length")
    if not clength and not opts.dont_add_content_length then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type .. "; boundary=" .. boundary
    end

    opts.body = body
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = encode_args(opts.query)
    opts.path = opts.path .. "?" .. qs
    opts.query = nil
  end

  local res, err = self:request(opts)
  if res then
    -- wrap the read_body() so it caches the result and can be called multiple
    -- times
    local reader = res.read_body
    res.read_body = function(self)
      if not self._cached_body and not self._cached_error then
        self._cached_body, self._cached_error = reader(self)
      end
      return self._cached_body, self._cached_error
    end

  elseif (err == "closed" or err == "connection reset by peer")
     and not is_reopen
     and self.reopen
     and can_reopen(opts.method)
  then
    ngx.log(ngx.INFO, "Re-opening connection to ", self.options.scheme, "://",
                      self.options.host, ":", self.options.port)

    self:_connect()
    return self:send(opts, true)
  end

  return res, err
end


--- Open or re-open the client TCP connection
function resty_http_proxy_mt:_connect()
  local opts = self.options

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.connect_timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
    opts.send_timeout    = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
    opts.read_timeout    = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  local _, err = self:connect(opts)
  if err then
    error("Could not connect to " ..
          (opts.host or "unknown") .. ":" .. (opts.port or "unknown") ..
          ": " .. err)
  end

  if opts.connect_timeout and
     opts.send_timeout    and
     opts.read_timeout
  then
    self:set_timeouts(opts.connect_timeout, opts.send_timeout, opts.read_timeout)
  else
    self:set_timeout(opts.timeout or 10000)
  end
end


-- Implements http_client:get("path", [options]), as well as post, put, etc.
-- These methods are equivalent to calling http_client:send, but are shorter
-- They also come with a built-in assert
for _, method_name in ipairs({"get", "post", "put", "patch", "delete", "head", "options"}) do
  resty_http_proxy_mt[method_name] = function(self, path, options)
    local full_options = kong.table.merge({ method = method_name:upper(), path = path}, options)
    return assert(self:send(full_options))
  end
end


--- Creates a http client from options.
-- Instead of using this client, you'll probably want to use the pre-configured
-- clients available as `proxy_client`, `admin_client`, etc. because these come
-- pre-configured and connected to the underlying Kong test instance.
--
-- @function http_client_opts
-- @param options connection and other options
-- @return http client
-- @see http_client:send
-- @see proxy_client
-- @see proxy_ssl_client
-- @see admin_client
-- @see admin_ssl_client
local function http_client_opts(options)
  if not options.scheme then
    options = kong_table.cycle_aware_deep_copy(options)
    options.scheme = "http"
    if options.port == 443 then
      options.scheme = "https"
    else
      options.scheme = "http"
    end
  end

  local self = setmetatable(assert(http.new()), resty_http_proxy_mt)

  self.options = options

  if options.reopen ~= nil then
    self.reopen = options.reopen
  end

  self:_connect()

  return self
end


--- Creates a http client.
-- Instead of using this client, you'll probably want to use the pre-configured
-- clients available as `proxy_client`, `admin_client`, etc. because these come
-- pre-configured and connected to the underlying Kong test instance.
--
-- @function http_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param timeout in seconds
-- @return http client
-- @see http_client:send
-- @see proxy_client
-- @see proxy_ssl_client
-- @see admin_client
-- @see admin_ssl_client
local function http_client(host, port, timeout)
  if type(host) == "table" then
    return http_client_opts(host)
  end

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  return http_client_opts({
    host = host,
    port = port,
    timeout = timeout,
  })
end


--- Returns the proxy port.
-- @function get_proxy_port
-- @param ssl (boolean) if `true` returns the ssl port
-- @param http2 (boolean) if `true` returns the http2 port
local function get_proxy_port(ssl, http2)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == ssl and (http2 == nil or entry.http2 == http2) then
      return entry.port
    end
  end
  error("No proxy port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the proxy ip.
-- @function get_proxy_ip
-- @param ssl (boolean) if `true` returns the ssl ip address
-- @param http2 (boolean) if `true` returns the http2 ip address
local function get_proxy_ip(ssl, http2)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == ssl and (http2 == nil or entry.http2 == http2) then
      return entry.ip
    end
  end
  error("No proxy ip found for ssl=" .. tostring(ssl), 2)
end


--- returns a pre-configured `http_client` for the Kong proxy port.
-- @function proxy_client
-- @param timeout (optional, number) the timeout to use
-- @param forced_port (optional, number) if provided will override the port in
-- the Kong configuration with this port
local function proxy_client(timeout, forced_port, forced_ip)
  local proxy_ip = get_proxy_ip(false)
  local proxy_port = get_proxy_port(false)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = forced_ip or proxy_ip,
    port = forced_port or proxy_port,
    timeout = timeout or 60000,
  })
end


--- returns a pre-configured `http_client` for the Kong SSL proxy port.
-- @function proxy_ssl_client
-- @param timeout (optional, number) the timeout to use
-- @param sni (optional, string) the sni to use
local function proxy_ssl_client(timeout, sni)
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  local client = http_client_opts({
    scheme = "https",
    host = proxy_ip,
    port = proxy_port,
    timeout = timeout or 60000,
    ssl_verify = false,
    ssl_server_name = sni,
  })
    return client
end


--- returns a pre-configured `http_client` for the Kong admin port.
-- @function admin_client
-- @param timeout (optional, number) the timeout to use
-- @param forced_port (optional, number) if provided will override the port in
-- the Kong configuration with this port
local function admin_client(timeout, forced_port)
  local admin_ip, admin_port
  for _, entry in ipairs(conf.admin_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No http-admin found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = admin_ip,
    port = forced_port or admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
end

--- returns a pre-configured `http_client` for the Kong admin SSL port.
-- @function admin_ssl_client
-- @param timeout (optional, number) the timeout to use
local function admin_ssl_client(timeout)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  local admin_ip, admin_port
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == true then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No https-admin found in the configuration")
  local client = http_client_opts({
    scheme = "https",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
  return client
end

--- returns a pre-configured `http_client` for the Kong Admin GUI.
-- @function admin_gui_client
-- @tparam[opt=60000] number timeout the timeout to use
-- @tparam[opt] number forced_port if provided will override the port in
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
local function admin_gui_client(timeout, forced_port)
  local admin_ip = "127.0.0.1"
  local admin_port
  for _, entry in ipairs(conf.admin_gui_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  admin_port = forced_port or admin_port
  assert(admin_port, "No http-admin found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
end

--- returns a pre-configured `http_client` for the Kong admin GUI SSL port.
-- @function admin_gui_ssl_client
-- @tparam[opt=60000] number timeout the timeout to use
-- @tparam[opt] number forced_port if provided will override the port in
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
local function admin_gui_ssl_client(timeout, forced_port)
  local admin_ip = "127.0.0.1"
  local admin_port
  for _, entry in ipairs(conf.admin_gui_listeners) do
    if entry.ssl == true then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  admin_port = forced_port or admin_port
  assert(admin_port, "No https-admin found in the configuration")
  return http_client_opts({
    scheme = "https",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
end


----------------
-- HTTP2 and GRPC clients
-- @section Shell-helpers


-- Generate grpcurl flags from a table of `flag-value`. If `value` is not a
-- string, value is ignored and `flag` is passed as is.
local function gen_grpcurl_opts(opts_t)
  local opts_l = {}

  for opt, val in pairs(opts_t) do
    if val ~= false then
      opts_l[#opts_l + 1] = opt .. " " .. (type(val) == "string" and val or "")
    end
  end

  return table.concat(opts_l, " ")
end


--- Creates an HTTP/2 client using golang's http2 package.
--- Sets `KONG_TEST_DEBUG_HTTP2=1` env var to print debug messages.
-- @function http2_client
-- @param host hostname to connect to
-- @param port port to connect to
local function http2_client(host, port, tls)
  local port = assert(port)
  tls = tls or false

  -- Note: set `GODEBUG=http2debug=1` is helpful if you are debugging this go program
  local tool_path = "bin/h2client"
  local http2_debug
  -- note: set env var "KONG_TEST_DEBUG_HTTP2" !! the "_TEST" will be dropped
  if os.getenv("KONG_DEBUG_HTTP2") then
    http2_debug = true
    tool_path = "GODEBUG=http2debug=1 bin/h2client"
  end


  local meta = {}
  meta.__call = function(_, opts)
    local headers = opts and opts.headers
    local timeout = opts and opts.timeout
    local body = opts and opts.body
    local path = opts and opts.path or ""
    local http1 = opts and opts.http_version == "HTTP/1.1"

    local url = (tls and "https" or "http") .. "://" .. host .. ":" .. port .. path

    local cmd = string.format("%s -url %s -skip-verify", tool_path, url)

    if headers then
      local h = {}
      for k, v in pairs(headers) do
        table.insert(h, string.format("%s=%s", k, v))
      end
      cmd = cmd .. " -headers " .. table.concat(h, ",")
    end

    if timeout then
      cmd = cmd .. " -timeout " .. timeout
    end

    if http1 then
      cmd = cmd .. " -http1"
    end

    --shell.run does not support '<'
    if body then
      cmd = cmd .. " -post"
    end

    if http2_debug then
      print("HTTP/2 cmd:\n" .. cmd)
    end

    --100MB for retrieving stdout & stderr
    local ok, stdout, stderr = shell.run(cmd, body, 0, 1024*1024*100)
    assert(ok, stderr)

    if http2_debug then
      print("HTTP/2 debug:\n")
      print(stderr)
    end

    local stdout_decoded = cjson.decode(stdout)
    if not stdout_decoded then
      error("Failed to decode h2client output: " .. stdout)
    end

    local headers = stdout_decoded.headers
    headers.get = function(_, key)
      if string.sub(key, 1, 1) == ":" then
        key = string.sub(key, 2)
      end
      return headers[key]
    end
    setmetatable(headers, {
      __index = function(headers, key)
        for k, v in pairs(headers) do
          if key:lower() == k:lower() then
            return v
          end
        end
      end
    })
    return stdout_decoded.body, headers
  end

  return setmetatable({}, meta)
end


--- returns a pre-configured cleartext `http2_client` for the Kong proxy port.
-- @function proxy_client_h2c
-- @return http2 client
local function proxy_client_h2c()
  local proxy_ip = get_proxy_ip(false, true)
  local proxy_port = get_proxy_port(false, true)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port)
end


--- returns a pre-configured TLS `http2_client` for the Kong SSL proxy port.
-- @function proxy_client_h2
-- @return http2 client
local function proxy_client_h2()
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port, true)
end


--- Creates a gRPC client, based on the grpcurl CLI.
-- @function grpc_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param opts table with options supported by grpcurl
-- @return grpc client
local function grpc_client(host, port, opts)
  local host = assert(host)
  local port = assert(tostring(port))

  opts = opts or {}
  if not opts["-proto"] then
    opts["-proto"] = CONSTANTS.MOCK_GRPC_UPSTREAM_PROTO_PATH
  end

  return setmetatable({
    opts = opts,
    cmd_template = string.format("bin/grpcurl %%s %s:%s %%s", host, port)

  }, {
    __call = function(t, args)
      local service = assert(args.service)
      local body = args.body
      local arg_opts = args.opts or {}

      local t_body = type(body)
      if t_body ~= "nil" then
        if t_body == "table" then
          body = cjson.encode(body)
        end

        arg_opts["-d"] = string.format("'%s'", body)
      end

      local cmd_opts = gen_grpcurl_opts(pl_tablex.merge(t.opts, arg_opts, true))
      local cmd = string.format(t.cmd_template, cmd_opts, service)
      local ok, _, out, err = shell.exec(cmd, true)

      if ok then
        return ok, ("%s%s"):format(out or "", err or "")
      else
        return nil, ("%s%s"):format(out or "", err or "")
      end
    end
  })
end


--- returns a pre-configured `grpc_client` for the Kong proxy port.
-- @function proxy_client_grpc
-- @param host hostname to connect to
-- @param port port to connect to
-- @return grpc client
local function proxy_client_grpc(host, port)
  local proxy_ip = host or get_proxy_ip(false, true)
  local proxy_port = port or get_proxy_port(false, true)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return grpc_client(proxy_ip, proxy_port, {["-plaintext"] = true})
end


--- returns a pre-configured `grpc_client` for the Kong SSL proxy port.
-- @function proxy_client_grpcs
-- @param host hostname to connect to
-- @param port port to connect to
-- @return grpc client
local function proxy_client_grpcs(host, port)
  local proxy_ip = host or get_proxy_ip(true, true)
  local proxy_port = port or get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  return grpc_client(proxy_ip, proxy_port, {["-insecure"] = true})
end


---
-- Reconfiguration completion detection helpers
--

local MAX_RETRY_TIME = 10

--- Set up admin client and proxy client to so that interactions with the proxy client
-- wait for preceding admin API client changes to have completed.

-- @function make_synchronized_clients
-- @param clients table with admin_client and proxy_client fields (both optional)
-- @return admin_client, proxy_client

local function make_synchronized_clients(clients)
  clients = clients or {}
  local synchronized_proxy_client = clients.proxy_client or proxy_client()
  local synchronized_admin_client = clients.admin_client or admin_client()

  -- Install the reconfiguration completion detection plugin
  local res = synchronized_admin_client:post("/plugins", {
    headers = { ["Content-Type"] = "application/json" },
    body = {
      name = "reconfiguration-completion",
      config = {
        version = "0",
      }
    },
  })
  local body = luassert.res_status(201, res)
  local plugin = cjson.decode(body)
  local plugin_id = plugin.id

  -- Wait until the plugin is active on the proxy path, indicated by the presence of the X-Kong-Reconfiguration-Status header
  luassert.eventually(function()
    res = synchronized_proxy_client:get("/non-existent-proxy-path")
    luassert.res_status(404, res)
    luassert.equals("unknown", res.headers['x-kong-reconfiguration-status'])
  end)
          .has_no_error()

  -- Save the original request functions for the admin and proxy client
  local proxy_request = synchronized_proxy_client.request
  local admin_request = synchronized_admin_client.request

  local current_version = 0 -- incremented whenever a configuration change is made through the admin API
  local last_configured_version = 0 -- current version of the reconfiguration-completion plugin's configuration

  -- Wrap the admin API client request
  function synchronized_admin_client.request(client, opts)
    -- Whenever the configuration is changed through the admin API, increment the current version number
    if opts.method == "POST" or opts.method == "PUT" or opts.method == "PATCH" or opts.method == "DELETE" then
      current_version = current_version + 1
    end
    return admin_request(client, opts)
  end

  function synchronized_admin_client.synchronize_sibling(self, sibling)
    sibling.request = self.request
  end

  -- Wrap the proxy client request
  function synchronized_proxy_client.request(client, opts)
    -- If the configuration has been changed through the admin API, update the version number in the
    -- reconfiguration-completion plugin.
    if current_version > last_configured_version then
      last_configured_version = current_version
      res = admin_request(synchronized_admin_client, {
        method = "PATCH",
        path = "/plugins/" .. plugin_id,
        headers = { ["Content-Type"] = "application/json" },
        body = cjson.encode({
          config = {
            version = tostring(current_version),
          }
        }),
      })
      luassert.res_status(200, res)
    end

    -- Retry the request until the reconfiguration is complete and the reconfiguration completion
    -- plugin on the database has been updated to the current version.
    if not opts.headers then
      opts.headers = {}
    end
    opts.headers["If-Kong-Configuration-Version"] = tostring(current_version)
    local retry_until = ngx.now() + MAX_RETRY_TIME
    local err
    :: retry ::
    res, err = proxy_request(client, opts)
    if err then
      return res, err
    end
    if res.headers['x-kong-reconfiguration-status'] ~= "complete" then
      res:read_body()
      ngx.sleep(res.headers['retry-after'] or 1)
      if ngx.now() < retry_until then
        goto retry
      end
      return nil, "reconfiguration did not occur within " .. MAX_RETRY_TIME .. " seconds"
    end
    return res, err
  end

  function synchronized_proxy_client.synchronize_sibling(self, sibling)
    sibling.request = self.request
  end

  return synchronized_proxy_client, synchronized_admin_client
end


--- Simulate a Hybrid mode DP and connect to the CP specified in `opts`.
-- @function clustering_client
-- @param opts Options to use, the `host`, `port`, `cert` and `cert_key` fields
-- are required.
-- Other fields that can be overwritten are:
-- `node_hostname`, `node_id`, `node_version`, `node_plugins_list`. If absent,
-- they are automatically filled.
-- @return msg if handshake succeeded and initial message received from CP or nil, err
local function clustering_client(opts)
  assert(opts.host)
  assert(opts.port)
  assert(opts.cert)
  assert(opts.cert_key)

  local pl_file = require("pl.file")
  local ssl = require("ngx.ssl")
  local inflate_gzip = require("kong.tools.gzip").inflate_gzip
  local ws_client = require("resty.websocket.client")
  local DB = require("spec.internal.db")

  local c = assert(ws_client:new())
  local uri = "wss://" .. opts.host .. ":" .. opts.port ..
              "/v1/outlet?node_id=" .. (opts.node_id or uuid()) ..
              "&node_hostname=" .. (opts.node_hostname or kong.node.get_hostname()) ..
              "&node_version=" .. (opts.node_version or CONSTANTS.KONG_VERSION)

  local conn_opts = {
    ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
    client_cert = assert(ssl.parse_pem_cert(assert(pl_file.read(opts.cert)))),
    client_priv_key = assert(ssl.parse_pem_priv_key(assert(pl_file.read(opts.cert_key)))),
    server_name = opts.server_name or "kong_clustering",
  }

  local res, err = c:connect(uri, conn_opts)
  if not res then
    return nil, err
  end
  local payload = assert(cjson.encode({ type = "basic_info",
                                        plugins = opts.node_plugins_list or
                                                  DB.get_plugins_list(),
                                        labels = opts.node_labels,
                                        process_conf = opts.node_process_conf,
                                      }))
  assert(c:send_binary(payload))

  assert(c:send_ping(string.rep("0", 32)))

  local data, typ, err
  data, typ, err = c:recv_frame()
  c:close()

  if typ == "binary" then
    local odata = assert(inflate_gzip(data))
    local msg = assert(cjson.decode(odata))
    return msg

  elseif typ == "pong" then
    return "PONG"
  end

  return nil, "unknown frame from CP: " .. (typ or err)
end


return {
  get_proxy_ip = get_proxy_ip,
  get_proxy_port = get_proxy_port,

  http_client = http_client,
  grpc_client = grpc_client,
  http2_client = http2_client,

  proxy_client = proxy_client,
  proxy_ssl_client = proxy_ssl_client,
  proxy_client_grpc = proxy_client_grpc,
  proxy_client_grpcs = proxy_client_grpcs,
  proxy_client_h2c = proxy_client_h2c,
  proxy_client_h2 = proxy_client_h2,

  admin_client = admin_client,
  admin_ssl_client = admin_ssl_client,

  admin_gui_client = admin_gui_client,
  admin_gui_ssl_client = admin_gui_ssl_client,

  make_synchronized_clients = make_synchronized_clients,

  clustering_client = clustering_client,
}

