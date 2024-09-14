------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local cjson = require "cjson.safe"
local kong_table = require "kong.tools.table"
local http = require "resty.http"
local log = require "kong.cmd.utils.log"
local ssl = require "ngx.ssl"
local ws_client = require "resty.websocket.client"
local table_clone = require "table.clone"
local https_server = require "spec.fixtures.https_server"
local stress_generator = require "spec.fixtures.stress_generator"
local lfs = require "lfs"
local luassert = require "luassert.assert"
local uuid = require("kong.tools.uuid").uuid


local reload_module = require("spec.internal.module").reload


log.set_lvl(log.levels.quiet) -- disable stdout logs in tests


-- reload some modules when env or _G changes
local CONSTANTS = reload_module("spec.internal.constants")
local conf = reload_module("spec.internal.conf")
local shell = reload_module("spec.internal.shell")
local misc = reload_module("spec.internal.misc")
local DB = reload_module("spec.internal.db")
local grpc = reload_module("spec.internal.grpc")
local dns_mock = reload_module("spec.internal.dns")
local asserts = reload_module("spec.internal.asserts") -- luacheck: ignore
local pid = reload_module("spec.internal.pid")
local cmd = reload_module("spec.internal.cmd")
local server = reload_module("spec.internal.server")


local exec = shell.exec
local kong_exec = shell.kong_exec


local get_available_port
do
  local USED_PORTS = {}

  function get_available_port()
    for _i = 1, 10 do
      local port = math.random(10000, 30000)

      if not USED_PORTS[port] then
          USED_PORTS[port] = true

          local ok = shell.run("netstat -lnt | grep \":" .. port .. "\" > /dev/null", nil, 0)

          if not ok then
            -- return code of 1 means `grep` did not found the listening port
            return port

          else
            print("Port " .. port .. " is occupied, trying another one")
          end
      end
    end

    error("Could not find an available port after 10 tries")
  end
end


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
  local cjson = require "cjson"
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
      local ok, _, out, err = exec(cmd, true)

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

--------------------
-- Custom assertions
--
-- @section assertions

require("spec.helpers.wait")

--- Waits until a specific condition is met.
-- The check function will repeatedly be called (with a fixed interval), until
-- the condition is met. Throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_until
-- @param f check function that should return `truthy` when the condition has
-- been met
-- @param timeout (optional) maximum time to wait after which an error is
-- thrown, defaults to 5.
-- @param step (optional) interval between checks, defaults to 0.05.
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
-- @usage
-- -- wait 10 seconds for a file "myfilename" to appear
-- helpers.wait_until(function() return file_exist("myfilename") end, 10)
local function wait_until(f, timeout, step)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  luassert.wait_until({
    condition = "truthy",
    fn = f,
    timeout = timeout,
    step = step,
  })
end


--- Waits until no Lua error occurred
-- The check function will repeatedly be called (with a fixed interval), until
-- there is no Lua error occurred
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function pwait_until
-- @param f check function
-- @param timeout (optional) maximum time to wait after which an error is
-- thrown, defaults to 5.
-- @param step (optional) interval between checks, defaults to 0.05.
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
local function pwait_until(f, timeout, step)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  luassert.wait_until({
    condition = "no_error",
    fn = f,
    timeout = timeout,
    step = step,
  })
end


--- Wait for some timers, throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_timer
-- @tparam string timer_name_pattern the call will apply to all timers matching this string
-- @tparam boolean plain if truthy, the `timer_name_pattern` will be matched plain, so without pattern matching
-- @tparam string mode one of: "all-finish", "all-running", "any-finish", "any-running", or "worker-wide-all-finish"
--
-- any-finish: At least one of the timers that were matched finished
--
-- all-finish: All timers that were matched finished
--
-- any-running: At least one of the timers that were matched is running
--
-- all-running: All timers that were matched are running
--
-- worker-wide-all-finish: All the timers in the worker that were matched finished
-- @tparam number timeout maximum time to wait (optional, default: 2)
-- @tparam number admin_client_timeout, to override the default timeout setting (optional)
-- @tparam number forced_admin_port to override the default port of admin API (optional)
-- @usage helpers.wait_timer("rate-limiting", true, "all-finish", 10)
local function wait_timer(timer_name_pattern, plain,
                          mode, timeout,
                          admin_client_timeout, forced_admin_port)
  if not timeout then
    timeout = 2
  end

  local _admin_client

  local all_running_each_worker = nil
  local all_finish_each_worker = nil
  local any_running_each_worker = nil
  local any_finish_each_worker = nil

  wait_until(function ()
    if _admin_client then
      _admin_client:close()
    end

    _admin_client = admin_client(admin_client_timeout, forced_admin_port)
    local res = assert(_admin_client:get("/timers"))
    local body = luassert.res_status(200, res)
    local json = assert(cjson.decode(body))
    local worker_id = json.worker.id
    local worker_count = json.worker.count

    if not all_running_each_worker then
      all_running_each_worker = {}
      all_finish_each_worker = {}
      any_running_each_worker = {}
      any_finish_each_worker = {}

      for i = 0, worker_count - 1 do
        all_running_each_worker[i] = false
        all_finish_each_worker[i] = false
        any_running_each_worker[i] = false
        any_finish_each_worker[i] = false
      end
    end

    local is_matched = false

    for timer_name, timer in pairs(json.stats.timers) do
      if string.find(timer_name, timer_name_pattern, 1, plain) then
        is_matched = true

        all_finish_each_worker[worker_id] = false

        if timer.is_running then
          all_running_each_worker[worker_id] = true
          any_running_each_worker[worker_id] = true
          goto continue
        end

        all_running_each_worker[worker_id] = false

        goto continue
      end

      ::continue::
    end

    if not is_matched then
      any_finish_each_worker[worker_id] = true
      all_finish_each_worker[worker_id] = true
    end

    local all_running = false

    local all_finish = false
    local all_finish_worker_wide = true

    local any_running = false
    local any_finish = false

    for _, v in pairs(all_running_each_worker) do
      all_running = all_running or v
    end

    for _, v in pairs(all_finish_each_worker) do
      all_finish = all_finish or v
      all_finish_worker_wide = all_finish_worker_wide and v
    end

    for _, v in pairs(any_running_each_worker) do
      any_running = any_running or v
    end

    for _, v in pairs(any_finish_each_worker) do
      any_finish = any_finish or v
    end

    if mode == "all-running" then
      return all_running
    end

    if mode == "all-finish" then
      return all_finish
    end

    if mode == "worker-wide-all-finish" then
      return all_finish_worker_wide
    end

    if mode == "any-finish" then
      return any_finish
    end

    if mode == "any-running" then
      return any_running
    end

    error("unexpected error")
  end, timeout)
end


--- Waits for invalidation of a cached key by polling the mgt-api
-- and waiting for a 404 response. Throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_for_invalidation
-- @param key (string) the cache-key to check
-- @param timeout (optional) in seconds (for default see `wait_until`).
-- @return nothing. It returns when the key is invalidated, or throws an error
-- when it times out.
-- @usage
-- local cache_key = "abc123"
-- helpers.wait_for_invalidation(cache_key, 10)
local function wait_for_invalidation(key, timeout)
  -- TODO: this code is duplicated all over the codebase,
  -- search codebase for "/cache/" endpoint
  local api_client = admin_client()
  wait_until(function()
    local res = api_client:get("/cache/" .. key)
    res:read_body()
    return res.status == 404
  end, timeout)
end


--- Wait for all targets, upstreams, services, and routes update
--
-- NOTE: this function is not available for DBless-mode
-- @function wait_for_all_config_update
-- @tparam[opt] table opts a table contains params
-- @tparam[opt=30] number opts.timeout maximum seconds to wait, defatuls is 30
-- @tparam[opt] number opts.admin_client_timeout to override the default timeout setting
-- @tparam[opt] number opts.forced_admin_port to override the default Admin API port
-- @tparam[opt] bollean opts.stream_enabled to enable stream module
-- @tparam[opt] number opts.proxy_client_timeout to override the default timeout setting
-- @tparam[opt] number opts.forced_proxy_port to override the default proxy port
-- @tparam[opt] number opts.stream_port to set the stream port
-- @tparam[opt] string opts.stream_ip to set the stream ip
-- @tparam[opt=false] boolean opts.override_global_rate_limiting_plugin to override the global rate-limiting plugin in waiting
-- @tparam[opt=false] boolean opts.override_global_key_auth_plugin to override the global key-auth plugin in waiting
local function wait_for_all_config_update(opts)
  opts = opts or {}
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end
  local timeout = opts.timeout or 30
  local admin_client_timeout = opts.admin_client_timeout
  local forced_admin_port = opts.forced_admin_port
  local proxy_client_timeout = opts.proxy_client_timeout
  local forced_proxy_port = opts.forced_proxy_port
  local stream_port = opts.stream_port
  local stream_ip = opts.stream_ip
  local stream_enabled = opts.stream_enabled or false
  local override_rl = opts.override_global_rate_limiting_plugin or false
  local override_auth = opts.override_global_key_auth_plugin or false
  local headers = opts.override_default_headers or { ["Content-Type"] = "application/json" }
  local disable_ipv6 = opts.disable_ipv6 or false

  local function call_admin_api(method, path, body, expected_status, headers)
    local client = admin_client(admin_client_timeout, forced_admin_port)

    local res

    if string.upper(method) == "POST" then
      res = client:post(path, {
        headers = headers,
        body = body,
      })

    elseif string.upper(method) == "DELETE" then
      res = client:delete(path, {
        headers = headers
      })
    end

    local ok, json_or_nil_or_err = pcall(function ()
      assert(res.status == expected_status, "unexpected response code: " .. res.status)

      if string.upper(method) == "DELETE" then
        return
      end

      local json = cjson.decode((res:read_body()))
      assert(json ~= nil, "unexpected response body")
      return json
    end)

    client:close()

    assert(ok, json_or_nil_or_err)

    return json_or_nil_or_err
  end

  local upstream_id, target_id, service_id, route_id
  local stream_upstream_id, stream_target_id, stream_service_id, stream_route_id
  local consumer_id, rl_plugin_id, key_auth_plugin_id, credential_id
  local upstream_name = "really.really.really.really.really.really.really.mocking.upstream.test"
  local service_name = "really-really-really-really-really-really-really-mocking-service"
  local stream_upstream_name = "stream-really.really.really.really.really.really.really.mocking.upstream.test"
  local stream_service_name = "stream-really-really-really-really-really-really-really-mocking-service"
  local route_path = "/really-really-really-really-really-really-really-mocking-route"
  local key_header_name = "really-really-really-really-really-really-really-mocking-key"
  local consumer_name = "really-really-really-really-really-really-really-mocking-consumer"
  local test_credentials = "really-really-really-really-really-really-really-mocking-credentials"

  local host = "localhost"
  local port = get_available_port()

  local server = https_server.new(port, host, "http", nil, 1, nil, disable_ipv6)

  server:start()

  -- create mocking upstream
  local res = assert(call_admin_api("POST",
                             "/upstreams",
                             { name = upstream_name },
                             201, headers))
  upstream_id = res.id

  -- create mocking target to mocking upstream
  res = assert(call_admin_api("POST",
                       string.format("/upstreams/%s/targets", upstream_id),
                       { target = host .. ":" .. port },
                       201, headers))
  target_id = res.id

  -- create mocking service to mocking upstream
  res = assert(call_admin_api("POST",
                       "/services",
                       { name = service_name, url = "http://" .. upstream_name .. "/always_200" },
                       201, headers))
  service_id = res.id

  -- create mocking route to mocking service
  res = assert(call_admin_api("POST",
                       string.format("/services/%s/routes", service_id),
                       { paths = { route_path }, strip_path = true, path_handling = "v0",},
                       201, headers))
  route_id = res.id

  if override_rl then
    -- create rate-limiting plugin to mocking mocking service
    res = assert(call_admin_api("POST",
                                string.format("/services/%s/plugins", service_id),
                                { name = "rate-limiting", config = { minute = 999999, policy = "local" } },
                                201, headers))
    rl_plugin_id = res.id
  end

  if override_auth then
    -- create key-auth plugin to mocking mocking service
    res = assert(call_admin_api("POST",
                                string.format("/services/%s/plugins", service_id),
                                { name = "key-auth", config = { key_names = { key_header_name } } },
                                201, headers))
    key_auth_plugin_id = res.id

    -- create consumer
    res = assert(call_admin_api("POST",
                                "/consumers",
                                { username = consumer_name },
                                201, headers))
      consumer_id = res.id

    -- create credential to key-auth plugin
    res = assert(call_admin_api("POST",
                                string.format("/consumers/%s/key-auth", consumer_id),
                                { key = test_credentials },
                                201, headers))
    credential_id = res.id
  end

  if stream_enabled then
      -- create mocking upstream
    local res = assert(call_admin_api("POST",
                              "/upstreams",
                              { name = stream_upstream_name },
                              201, headers))
    stream_upstream_id = res.id

    -- create mocking target to mocking upstream
    res = assert(call_admin_api("POST",
                        string.format("/upstreams/%s/targets", stream_upstream_id),
                        { target = host .. ":" .. port },
                        201, headers))
    stream_target_id = res.id

    -- create mocking service to mocking upstream
    res = assert(call_admin_api("POST",
                        "/services",
                        { name = stream_service_name, url = "tcp://" .. stream_upstream_name },
                        201, headers))
    stream_service_id = res.id

    -- create mocking route to mocking service
    res = assert(call_admin_api("POST",
                        string.format("/services/%s/routes", stream_service_id),
                        { destinations = { { port = stream_port }, }, protocols = { "tcp" },},
                        201, headers))
    stream_route_id = res.id
  end

  local ok, err = pcall(function ()
    -- wait for mocking route ready
    pwait_until(function ()
      local proxy = proxy_client(proxy_client_timeout, forced_proxy_port)

      if override_auth then
        res = proxy:get(route_path, { headers = { [key_header_name] = test_credentials } })

      else
        res = proxy:get(route_path)
      end

      local ok, err = pcall(assert, res.status == 200)
      proxy:close()
      assert(ok, err)
    end, timeout / 2)

    if stream_enabled then
      pwait_until(function ()
        local proxy = proxy_client(proxy_client_timeout, stream_port, stream_ip)

        res = proxy:get("/always_200")
        local ok, err = pcall(assert, res.status == 200)
        proxy:close()
        assert(ok, err)
      end, timeout)
    end
  end)
  if not ok then
    server:shutdown()
    error(err)
  end

  -- delete mocking configurations
  if override_auth then
    call_admin_api("DELETE", string.format("/consumers/%s/key-auth/%s", consumer_id, credential_id), nil, 204, headers)
    call_admin_api("DELETE", string.format("/consumers/%s", consumer_id), nil, 204, headers)
    call_admin_api("DELETE", "/plugins/" .. key_auth_plugin_id, nil, 204, headers)
  end

  if override_rl then
    call_admin_api("DELETE", "/plugins/" .. rl_plugin_id, nil, 204, headers)
  end

  call_admin_api("DELETE", "/routes/" .. route_id, nil, 204, headers)
  call_admin_api("DELETE", "/services/" .. service_id, nil, 204, headers)
  call_admin_api("DELETE", string.format("/upstreams/%s/targets/%s", upstream_id, target_id), nil, 204, headers)
  call_admin_api("DELETE", "/upstreams/" .. upstream_id, nil, 204, headers)

  if stream_enabled then
    call_admin_api("DELETE", "/routes/" .. stream_route_id, nil, 204, headers)
    call_admin_api("DELETE", "/services/" .. stream_service_id, nil, 204, headers)
    call_admin_api("DELETE", string.format("/upstreams/%s/targets/%s", stream_upstream_id, stream_target_id), nil, 204, headers)
    call_admin_api("DELETE", "/upstreams/" .. stream_upstream_id, nil, 204, headers)
  end

  ok, err = pcall(function ()
    -- wait for mocking configurations to be deleted
    pwait_until(function ()
      local proxy = proxy_client(proxy_client_timeout, forced_proxy_port)
      res  = proxy:get(route_path)
      local ok, err = pcall(assert, res.status == 404)
      proxy:close()
      assert(ok, err)
    end, timeout / 2)
  end)

  server:shutdown()

  if not ok then
    error(err)
  end

end


--- Waits for a file to meet a certain condition
-- The check function will repeatedly be called (with a fixed interval), until
-- there is no Lua error occurred
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_for_file
-- @tparam string mode one of:
--
-- "file", "directory", "link", "socket", "named pipe", "char device", "block device", "other"
--
-- @tparam string path the file path
-- @tparam[opt=10] number timeout maximum seconds to wait
local function wait_for_file(mode, path, timeout)
  pwait_until(function()
    local result, err = lfs.attributes(path, "mode")
    local msg = string.format("failed to wait for the mode (%s) of '%s': %s",
                              mode, path, tostring(err))
    assert(result == mode, msg)
  end, timeout or 10)
end


local wait_for_file_contents
do
  --- Wait until a file exists and is non-empty.
  --
  -- If, after the timeout is reached, the file does not exist, is not
  -- readable, or is empty, an assertion error will be raised.
  --
  -- @function wait_for_file_contents
  -- @param fname the filename to wait for
  -- @param timeout (optional) maximum time to wait after which an error is
  -- thrown, defaults to 10.
  -- @return contents the file contents, as a string
  function wait_for_file_contents(fname, timeout)
    assert(type(fname) == "string",
           "filename must be a string")

    timeout = timeout or 10
    assert(type(timeout) == "number" and timeout >= 0,
           "timeout must be nil or a number >= 0")

    local data = pl_file.read(fname)
    if data and #data > 0 then
      return data
    end

    pcall(wait_until, function()
      data = pl_file.read(fname)
      return data and #data > 0
    end, timeout)

    assert(data, "file (" .. fname .. ") does not exist or is not readable"
                 .. " after " .. tostring(timeout) .. " seconds")

    assert(#data > 0, "file (" .. fname .. ") exists but is empty after " ..
                      tostring(timeout) .. " seconds")

    return data
  end
end


local function wait_until_no_common_workers(workers, expected_total, strategy)
  wait_until(function()
    local pok, admin_client = pcall(admin_client)
    if not pok then
      return false
    end
    local res = assert(admin_client:send {
      method = "GET",
      path = "/",
    })
    luassert.res_status(200, res)
    local json = cjson.decode(luassert.res_status(200, res))
    admin_client:close()

    local new_workers = json.pids.workers
    local total = 0
    local common = 0
    if new_workers then
      for _, v in ipairs(new_workers) do
        total = total + 1
        for _, v_old in ipairs(workers) do
          if v == v_old then
            common = common + 1
            break
          end
        end
      end
    end
    return common == 0 and total == (expected_total or total)
  end, 30)
end


local function get_kong_workers(expected_total)
  local workers

  wait_until(function()
    local pok, admin_client = pcall(admin_client)
    if not pok then
      return false
    end
    local res = admin_client:send {
      method = "GET",
      path = "/",
    }
    if not res or res.status ~= 200 then
      return false
    end
    local body = luassert.res_status(200, res)
    local json = cjson.decode(body)

    admin_client:close()

    workers = {}

    for _, item in ipairs(json.pids.workers) do
      if item ~= ngx.null then
        table.insert(workers, item)
      end
    end

    if expected_total and #workers ~= expected_total then
      return nil, ("expected %s worker pids, got %s"):format(expected_total,
                                                             #workers)

    elseif #workers == 0 then
      return nil, "GET / returned no worker pids"
    end

    return true
  end, 10)
  return workers
end


--- Reload Kong and wait all workers are restarted.
local function reload_kong(strategy, ...)
  local workers = get_kong_workers()
  local ok, err = kong_exec(...)
  if ok then
    wait_until_no_common_workers(workers, 1, strategy)
  end
  return ok, err
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

  local inflate_gzip = require("kong.tools.gzip").inflate_gzip

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


local make_temp_dir
do
  local seeded = false

  function make_temp_dir()
    if not seeded then
      ngx.update_time()
      math.randomseed(ngx.worker.pid() + ngx.now())
      seeded = true
    end

    local tmp
    local ok, err

    local tries = 1000
    for _ = 1, tries do
      local name = "/tmp/.kong-test" .. math.random()

      ok, err = pl_path.mkdir(name)

      if ok then
        tmp = name
        break
      end
    end

    assert(tmp ~= nil, "failed to create temporary directory " ..
                       "after " .. tostring(tries) .. " tries, " ..
                       "last error: " .. tostring(err))

    return tmp, function() pl_dir.rmtree(tmp) end
  end
end

-- This function is used for plugin compatibility test.
-- It will use the old version plugin by including the path of the old plugin
-- at the first of LUA_PATH.
-- The return value is a function which when called will recover the original
-- LUA_PATH and remove the temporary directory if it exists.
-- For an example of how to use it, please see:
-- plugins-ee/rate-limiting-advanced/spec/06-old-plugin-compatibility_spec.lua
-- spec/03-plugins/03-http-log/05-old-plugin-compatibility_spec.lua
local function use_old_plugin(name)
  assert(type(name) == "string", "must specify the plugin name")

  local old_plugin_path
  local temp_dir
  if pl_path.exists(CONSTANTS.OLD_VERSION_KONG_PATH .. "/kong/plugins/" .. name) then
    -- only include the path of the specified plugin into LUA_PATH
    -- and keep the directory structure 'kong/plugins/...'
    temp_dir = make_temp_dir()
    old_plugin_path = temp_dir
    local dest_dir = old_plugin_path .. "/kong/plugins"
    assert(pl_dir.makepath(dest_dir), "failed to makepath " .. dest_dir)
    assert(shell.run("cp -r " .. CONSTANTS.OLD_VERSION_KONG_PATH .. "/kong/plugins/" .. name .. " " .. dest_dir), "failed to copy the plugin directory")

  else
    error("the specified plugin " .. name .. " doesn't exist")
  end

  local origin_lua_path = os.getenv("LUA_PATH")
  -- put the old plugin path at first
  assert(misc.setenv("LUA_PATH", old_plugin_path .. "/?.lua;" .. old_plugin_path .. "/?/init.lua;" .. origin_lua_path), "failed to set LUA_PATH env")

  return function ()
    misc.setenv("LUA_PATH", origin_lua_path)
    if temp_dir then
      pl_dir.rmtree(temp_dir)
    end
  end
end


----------------
-- Variables/constants
-- @section exported-fields


--- Below is a list of fields/constants exported on the `helpers` module table:
-- @table helpers
-- @field dir The [`pl.dir` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.dir.html)
-- @field path The [`pl.path` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.path.html)
-- @field file The [`pl.file` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.file.html)
-- @field utils The [`pl.utils` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.utils.html)
-- @field test_conf The Kong test configuration. See also `get_running_conf` which might be slightly different.
-- @field test_conf_path The configuration file in use.
-- @field mock_upstream_hostname
-- @field mock_upstream_protocol
-- @field mock_upstream_host
-- @field mock_upstream_port
-- @field mock_upstream_url Base url constructed from the components
-- @field mock_upstream_ssl_protocol
-- @field mock_upstream_ssl_host
-- @field mock_upstream_ssl_port
-- @field mock_upstream_ssl_url Base url constructed from the components
-- @field mock_upstream_stream_port
-- @field mock_upstream_stream_ssl_port
-- @field mock_grpc_upstream_proto_path
-- @field grpcbin_host The host for grpcbin service, it can be set by env KONG_SPEC_TEST_GRPCBIN_HOST.
-- @field grpcbin_port The port (SSL disabled) for grpcbin service, it can be set by env KONG_SPEC_TEST_GRPCBIN_PORT.
-- @field grpcbin_ssl_port The port (SSL enabled) for grpcbin service it can be set by env KONG_SPEC_TEST_GRPCBIN_SSL_PORT.
-- @field grpcbin_url The URL (SSL disabled) for grpcbin service
-- @field grpcbin_ssl_url The URL (SSL enabled) for grpcbin service
-- @field redis_host The host for Redis, it can be set by env KONG_SPEC_TEST_REDIS_HOST.
-- @field redis_port The port (SSL disabled) for Redis, it can be set by env KONG_SPEC_TEST_REDIS_PORT.
-- @field redis_ssl_port The port (SSL enabled) for Redis, it can be set by env KONG_SPEC_TEST_REDIS_SSL_PORT.
-- @field redis_ssl_sni The server name for Redis, it can be set by env KONG_SPEC_TEST_REDIS_SSL_SNI.
-- @field zipkin_host The host for Zipkin service, it can be set by env KONG_SPEC_TEST_ZIPKIN_HOST.
-- @field zipkin_port the port for Zipkin service, it can be set by env KONG_SPEC_TEST_ZIPKIN_PORT.
-- @field otelcol_host The host for OpenTelemetry Collector service, it can be set by env KONG_SPEC_TEST_OTELCOL_HOST.
-- @field otelcol_http_port the port for OpenTelemetry Collector service, it can be set by env KONG_SPEC_TEST_OTELCOL_HTTP_PORT.
-- @field old_version_kong_path the path for the old version kong source code, it can be set by env KONG_SPEC_TEST_OLD_VERSION_KONG_PATH.
-- @field otelcol_zpages_port the port for OpenTelemetry Collector Zpages service, it can be set by env KONG_SPEC_TEST_OTELCOL_ZPAGES_PORT.
-- @field otelcol_file_exporter_path the path of for OpenTelemetry Collector's file exporter, it can be set by env KONG_SPEC_TEST_OTELCOL_FILE_EXPORTER_PATH.

----------
-- Exposed
----------
-- @export
  return {
  -- Penlight
  dir = pl_dir,
  path = pl_path,
  file = pl_file,
  utils = pl_utils,

  -- Kong testing properties
  db = DB.db,
  blueprints = DB.blueprints,
  get_db_utils = DB.get_db_utils,
  get_cache = DB.get_cache,
  bootstrap_database = DB.bootstrap_database,
  bin_path = CONSTANTS.BIN_PATH,
  test_conf = conf,
  test_conf_path = CONSTANTS.TEST_CONF_PATH,
  go_plugin_path = CONSTANTS.GO_PLUGIN_PATH,
  mock_upstream_hostname = CONSTANTS.MOCK_UPSTREAM_HOSTNAME,
  mock_upstream_protocol = CONSTANTS.MOCK_UPSTREAM_PROTOCOL,
  mock_upstream_host     = CONSTANTS.MOCK_UPSTREAM_HOST,
  mock_upstream_port     = CONSTANTS.MOCK_UPSTREAM_PORT,
  mock_upstream_url      = CONSTANTS.MOCK_UPSTREAM_PROTOCOL .. "://" ..
                           CONSTANTS.MOCK_UPSTREAM_HOST .. ':' ..
                           CONSTANTS.MOCK_UPSTREAM_PORT,

  mock_upstream_ssl_protocol = CONSTANTS.MOCK_UPSTREAM_SSL_PROTOCOL,
  mock_upstream_ssl_host     = CONSTANTS.MOCK_UPSTREAM_HOST,
  mock_upstream_ssl_port     = CONSTANTS.MOCK_UPSTREAM_SSL_PORT,
  mock_upstream_ssl_url      = CONSTANTS.MOCK_UPSTREAM_SSL_PROTOCOL .. "://" ..
                               CONSTANTS.MOCK_UPSTREAM_HOST .. ':' ..
                               CONSTANTS.MOCK_UPSTREAM_SSL_PORT,

  mock_upstream_stream_port     = CONSTANTS.MOCK_UPSTREAM_STREAM_PORT,
  mock_upstream_stream_ssl_port = CONSTANTS.MOCK_UPSTREAM_STREAM_SSL_PORT,
  mock_grpc_upstream_proto_path = CONSTANTS.MOCK_GRPC_UPSTREAM_PROTO_PATH,

  zipkin_host = CONSTANTS.ZIPKIN_HOST,
  zipkin_port = CONSTANTS.ZIPKIN_PORT,

  otelcol_host               = CONSTANTS.OTELCOL_HOST,
  otelcol_http_port          = CONSTANTS.OTELCOL_HTTP_PORT,
  otelcol_zpages_port        = CONSTANTS.OTELCOL_ZPAGES_PORT,
  otelcol_file_exporter_path = CONSTANTS.OTELCOL_FILE_EXPORTER_PATH,

  grpcbin_host     = CONSTANTS.GRPCBIN_HOST,
  grpcbin_port     = CONSTANTS.GRPCBIN_PORT,
  grpcbin_ssl_port = CONSTANTS.GRPCBIN_SSL_PORT,
  grpcbin_url      = string.format("grpc://%s:%d", CONSTANTS.GRPCBIN_HOST, CONSTANTS.GRPCBIN_PORT),
  grpcbin_ssl_url  = string.format("grpcs://%s:%d", CONSTANTS.GRPCBIN_HOST, CONSTANTS.GRPCBIN_SSL_PORT),

  redis_host     = CONSTANTS.REDIS_HOST,
  redis_port     = CONSTANTS.REDIS_PORT,
  redis_ssl_port = CONSTANTS.REDIS_SSL_PORT,
  redis_ssl_sni  = CONSTANTS.REDIS_SSL_SNI,
  redis_auth_port = CONSTANTS.REDIS_AUTH_PORT,

  blackhole_host = CONSTANTS.BLACKHOLE_HOST,

  old_version_kong_path = CONSTANTS.OLD_VERSION_KONG_PATH,

  -- Kong testing helpers
  execute = exec,
  dns_mock = dns_mock,
  kong_exec = kong_exec,
  get_version = cmd.get_version,
  get_running_conf = cmd.get_running_conf,
  http_client = http_client,
  grpc_client = grpc_client,
  http2_client = http2_client,
  make_synchronized_clients = make_synchronized_clients,
  wait_until = wait_until,
  pwait_until = pwait_until,
  wait_pid = pid.wait_pid,
  wait_timer = wait_timer,
  wait_for_all_config_update = wait_for_all_config_update,
  wait_for_file = wait_for_file,
  wait_for_file_contents = wait_for_file_contents,
  tcp_server = server.tcp_server,
  udp_server = server.udp_server,
  kill_tcp_server = server.kill_tcp_server,
  is_echo_server_ready = server.is_echo_server_ready,
  echo_server_reset = server.echo_server_reset,
  get_echo_server_received_data = server.get_echo_server_received_data,
  http_mock = server.http_mock,
  get_proxy_ip = get_proxy_ip,
  get_proxy_port = get_proxy_port,
  proxy_client = proxy_client,
  proxy_client_grpc = proxy_client_grpc,
  proxy_client_grpcs = proxy_client_grpcs,
  proxy_client_h2c = proxy_client_h2c,
  proxy_client_h2 = proxy_client_h2,
  admin_client = admin_client,
  admin_gui_client = admin_gui_client,
  proxy_ssl_client = proxy_ssl_client,
  admin_ssl_client = admin_ssl_client,
  admin_gui_ssl_client = admin_gui_ssl_client,
  prepare_prefix = cmd.prepare_prefix,
  clean_prefix = cmd.clean_prefix,
  clean_logfile = cmd.clean_logfile,
  wait_for_invalidation = wait_for_invalidation,
  each_strategy = DB.each_strategy,
  all_strategies = DB.all_strategies,
  validate_plugin_config_schema = DB.validate_plugin_config_schema,
  clustering_client = clustering_client,
  https_server = https_server,
  stress_generator = stress_generator,

  -- miscellaneous
  intercept = misc.intercept,
  openresty_ver_num = misc.openresty_ver_num,
  unindent = misc.unindent,
  make_yaml_file = misc.make_yaml_file,
  setenv = misc.setenv,
  unsetenv = misc.unsetenv,
  deep_sort = misc.deep_sort,
  generate_keys = misc.generate_keys,

  -- launching Kong subprocesses
  start_kong = cmd.start_kong,
  stop_kong = cmd.stop_kong,
  cleanup_kong = cmd.cleanup_kong,
  restart_kong = cmd.restart_kong,
  reload_kong = reload_kong,
  get_kong_workers = get_kong_workers,
  wait_until_no_common_workers = wait_until_no_common_workers,

  start_grpc_target = grpc.start_grpc_target,
  stop_grpc_target = grpc.stop_grpc_target,
  get_grpc_target_port = grpc.get_grpc_target_port,

  -- plugin compatibility test
  use_old_plugin = use_old_plugin,

  -- Only use in CLI tests from spec/02-integration/01-cmd
  kill_all = cmd.kill_all,

  with_current_ws = function(ws,fn, db)
    local old_ws = ngx.ctx.workspace
    ngx.ctx.workspace = nil
    ws = ws or {db.workspaces:select_by_name("default")}
    ngx.ctx.workspace = ws[1] and ws[1].id
    local res = fn()
    ngx.ctx.workspace = old_ws
    return res
  end,

  signal = cmd.signal,

  -- send signal to all Nginx workers, not including the master
  signal_workers = cmd.signal_workers,

  -- returns the plugins and version list that is used by Hybrid mode tests
  get_plugins_list = function()
    local PLUGINS_LIST = DB.get_plugins_list()
    assert(PLUGINS_LIST, "plugin list has not been initialized yet, " ..
                         "you must call get_db_utils first")
    return table_clone(PLUGINS_LIST)
  end,
  get_available_port = get_available_port,

  make_temp_dir = make_temp_dir,
}
