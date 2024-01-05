---
-- This namespace contains an instance of a logging facility, which is a
-- table containing all of the methods described below.
--
-- This instance is namespaced per plugin. Before
-- executing a plugin, Kong swaps this instance with a logging facility
-- dedicated to the plugin. This allows the logs to be prefixed with the
-- plugin's name for debugging purposes.
--
-- @module kong.log


local buffer = require "string.buffer"
local errlog = require "ngx.errlog"
local ngx_re = require "ngx.re"
local inspect = require "inspect"
local ngx_ssl = require "ngx.ssl"
local phase_checker = require "kong.pdk.private.phases"
local utils = require "kong.tools.utils"
local cycle_aware_deep_copy = utils.cycle_aware_deep_copy
local constants = require "kong.constants"

local sub = string.sub
local type = type
local pairs = pairs
local ipairs = ipairs
local find = string.find
local select = select
local concat = table.concat
local insert = table.insert
local getinfo = debug.getinfo
local reverse = string.reverse
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable
local ngx = ngx
local kong = kong
local check_phase = phase_checker.check
local split = utils.split
local byte = string.byte
local request_id_get = require "kong.tracing.request_id".get


local _PREFIX = "[kong] "
local _DEFAULT_FORMAT = "%file_src:%line_src %message"
local _DEFAULT_NAMESPACED_FORMAT = "%file_src:%line_src [%namespace] %message"
local PHASES = phase_checker.phases
local PHASES_LOG = PHASES.log
local QUESTION_MARK = byte("?")
local TYPE_NAMES = constants.RESPONSE_SOURCE.NAMES

local phases_with_ctx =
    phase_checker.new(PHASES.rewrite,
                      PHASES.access,
                      PHASES.header_filter,
                      PHASES.response,
                      PHASES.body_filter,
                      PHASES_LOG)
local _LEVELS = {
  debug = ngx.DEBUG,
  info = ngx.INFO,
  notice = ngx.NOTICE,
  warn = ngx.WARN,
  err = ngx.ERR,
  crit = ngx.CRIT,
  alert = ngx.ALERT,
  emerg = ngx.EMERG,
}


local _MODIFIERS = {
  ["%file_src"] = {
    flag = "S",
    info = function(info)
      local short_src = info.short_src
      if short_src then
        local rev_src = reverse(short_src)
        local idx = find(rev_src, "/", nil, true)
        if idx then
          return sub(short_src, #rev_src - idx + 2)
        end

        return short_src
      end
    end
  },

  ["%line_src"] = {
    flag = "l",
    info_key = "currentline",
  },

  ["%func_name"] = {
    flag = "n",
    info_key = "name",
  },

  ["%message"] = {
    message = true,
  },

  -- %namespace -- precompiled
}


local function parse_modifiers(format)
  local buf, err = ngx_re.split(format, [==[(?<!%)(%[a-z_]+)]==], nil, nil, 0)
  if not buf then
    return nil, "could not parse format: " .. err
  end

  local buf_len = #buf

  for i = 1, buf_len do
    local mod = _MODIFIERS[buf[i]]
    if mod then
      if mod.message then
        buf.message_idxs = buf.message_idxs or {}
        insert(buf.message_idxs, i)

      else
        buf.debug_flags = (buf.debug_flags or "") .. mod.flag

        buf.modifiers = buf.modifiers or {}
        insert(buf.modifiers, {
          idx = i,
          info = mod.info,
          info_key = mod.info_key,
        })
      end
    end
  end

  buf.n_modifiers = buf.modifiers and #buf.modifiers or 0
  buf.n_messages = buf.message_idxs and #buf.message_idxs or 0
  buf.n_len = buf_len

  return buf
end


local serializers = {
  [1] = function(buf, sep, to_string, ...)
    buf:put(to_string((select(1, ...))))
  end,

  [2] = function(buf, sep, to_string, ...)
    buf:put(to_string((select(1, ...)))):put(sep)
       :put(to_string((select(2, ...))))
  end,

  [3] = function(buf, sep, to_string, ...)
    buf:put(to_string((select(1, ...)))):put(sep)
       :put(to_string((select(2, ...)))):put(sep)
       :put(to_string((select(3, ...))))
  end,

  [4] = function(buf, sep, to_string, ...)
    buf:put(to_string((select(1, ...)))):put(sep)
       :put(to_string((select(2, ...)))):put(sep)
       :put(to_string((select(3, ...)))):put(sep)
       :put(to_string((select(4, ...))))
  end,

  [5] = function(buf, sep, to_string, ...)
    buf:put(to_string((select(1, ...)))):put(sep)
       :put(to_string((select(2, ...)))):put(sep)
       :put(to_string((select(3, ...)))):put(sep)
       :put(to_string((select(4, ...)))):put(sep)
       :put(to_string((select(5, ...))))
  end,
}


--- Writes a log line to the location specified by the current Nginx
-- configuration block's `error_log` directive, with the `notice` level (similar
-- to `print()`).
--
-- The Nginx `error_log` directive is set via the `log_level`, `proxy_error_log`
-- and `admin_error_log` Kong configuration properties.
--
-- Arguments given to this function are concatenated similarly to
-- `ngx.log()`, and the log line reports the Lua file and line number from
-- which it was invoked. Unlike `ngx.log()`, this function prefixes error
-- messages with `[kong]` instead of `[lua]`.
--
-- Arguments given to this function can be of any type, but table arguments
-- are converted to strings via `tostring` (thus potentially calling a
-- table's `__tostring` metamethod if set). This behavior differs from
-- `ngx.log()` (which only accepts table arguments if they define the
-- `__tostring` metamethod) with the intent to simplify its usage and be more
-- forgiving and intuitive.
--
-- Produced log lines have the following format when logging is invoked from
-- within the core:
--
-- ``` plain
-- [kong] %file_src:%line_src %message
-- ```
--
-- In comparison, log lines produced by plugins have the following format:
--
-- ``` plain
-- [kong] %file_src:%line_src [%namespace] %message
-- ```
--
-- Where:
--
-- * `%namespace`: The configured namespace (in this case, the plugin name).
-- * `%file_src`: The filename the log was called from.
-- * `%line_src`: The line number the log was called from.
-- * `%message`: The message, made of concatenated arguments given by the caller.
--
-- For example, the following call:
--
-- ``` lua
-- kong.log("hello ", "world")
-- ```
--
-- would, within the core, produce a log line similar to:
--
-- ``` plain
-- 2017/07/09 19:36:25 [notice] 25932#0: *1 [kong] some_file.lua:54 hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- If invoked from within a plugin (for example, `key-auth`) it would include the
-- namespace prefix:
--
-- ``` plain
-- 2017/07/09 19:36:25 [notice] 25932#0: *1 [kong] some_file.lua:54 [key-auth] hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- @function kong.log
-- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
-- @param ... All params will be concatenated and stringified before being sent to the log.
-- @return Nothing. Throws an error on invalid inputs.
--
-- @usage
-- kong.log("hello ", "world") -- alias to kong.log.notice()

---
-- Similar to `kong.log()`, but the produced log has the severity given by
-- `<level>`, instead of `notice`. The supported levels are:
--
-- * `kong.log.alert()`
-- * `kong.log.crit()`
-- * `kong.log.err()`
-- * `kong.log.warn()`
-- * `kong.log.notice()`
-- * `kong.log.info()`
-- * `kong.log.debug()`
--
-- Logs have the same format as that of `kong.log()`. For
-- example, the following call:
--
-- ``` lua
--  kong.log.err("hello ", "world")
-- ```
--
-- would, within the core, produce a log line similar to:
--
-- ``` plain
-- 2017/07/09 19:36:25 [error] 25932#0: *1 [kong] some_file.lua:54 hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- If invoked from within a plugin (for example, `key-auth`) it would include the
-- namespace prefix:
--
-- ``` plain
-- 2017/07/09 19:36:25 [error] 25932#0: *1 [kong] some_file.lua:54 [key-auth] hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- @function kong.log.LEVEL
-- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
-- @param ... All params will be concatenated and stringified before being sent to the log.
-- @return Nothing. Throws an error on invalid inputs.
-- @usage
-- kong.log.warn("something require attention")
-- kong.log.err("something failed: ", err)
-- kong.log.alert("something requires immediate action")
local function gen_log_func(lvl_const, imm_buf, to_string, stack_level, sep)
  local get_sys_filter_level = errlog.get_sys_filter_level
  local get_phase = ngx.get_phase

  to_string = to_string or tostring
  stack_level = stack_level or 2

  local variadic_buf = buffer.new()

  return function(...)
    local sys_log_level = nil

    if get_phase() ~= "init" then
      -- only grab sys_log_level after init_by_lua, where it is
      -- hard-coded
      sys_log_level = get_sys_filter_level()
    end

    if sys_log_level and lvl_const > sys_log_level then
      -- early exit if sys_log_level is higher than the current
      -- log call
      return
    end

    local n = select("#", ...)

    if imm_buf.debug_flags then
      local info = getinfo(stack_level, imm_buf.debug_flags)

      for i = 1, imm_buf.n_modifiers do
        local mod = imm_buf.modifiers[i]

        if not info then
          imm_buf[mod.idx] = "?"

        elseif mod.info then
          imm_buf[mod.idx] = mod.info(info) or "?"

        else
          imm_buf[mod.idx] = info[mod.info_key] or "?"
        end
      end
    end

    if serializers[n] then
      serializers[n](variadic_buf, sep or "" , to_string, ...)

    else
      for i = 1, n - 1 do
        variadic_buf:put(to_string((select(i, ...)))):put(sep or "")
      end
      variadic_buf:put(to_string((select(n, ...))))
    end

    local msg = variadic_buf:get()

    for i = 1, imm_buf.n_messages do
      imm_buf[imm_buf.message_idxs[i]] = msg
    end

    local fullmsg = concat(imm_buf, nil, 1, imm_buf.n_len)

    if to_string == inspect then
      local fullmsg_len = #fullmsg
      local WRAP = 120

      local i = fullmsg:find("\n") + 1
      local header = fullmsg:sub(1, i - 2) .. ("-"):rep(WRAP - i + 3) .. "+"

      errlog.raw_log(lvl_const, header)

      while i <= fullmsg_len do
        local part = sub(fullmsg, i, i + WRAP - 1)
        local nl = part:match("()\n")

        if nl then
          part = sub(fullmsg, i, i + nl - 2)
          i = i + nl

        else
          i = i + WRAP
        end

        part = part .. (" "):rep(WRAP - #part)
        errlog.raw_log(lvl_const, "|" .. part .. "|")

        if i > fullmsg_len then
          errlog.raw_log(lvl_const, "+" .. ("-"):rep(WRAP) .. "+")
        end
      end

      return
    end

    errlog.raw_log(lvl_const, fullmsg)
  end
end


--- Write a deprecation log line (similar to `kong.log.warn`).
--
-- Arguments given to this function can be of any type, but table arguments
-- are converted to strings via `tostring` (thus potentially calling a
-- table's `__tostring` metamethod if set). When the last argument is a table,
-- it is considered as a deprecation metadata. The table can include the
-- following properties:
--
-- ``` lua
-- {
--   after = "2.5.0",   -- deprecated after Kong version 2.5.0 (defaults to `nil`)
--   removal = "3.0.0", -- about to be removed with Kong version 3.0.0 (defaults to `nil`)
--   trace = true,      -- writes stack trace along with the deprecation message (defaults to `nil`)
-- }
-- ```
--
-- For example, the following call:
--
-- ``` lua
-- kong.log.deprecation("hello ", "world")
-- ```
--
-- would, within the core, produce a log line similar to:
--
-- ``` plain
-- 2017/07/09 19:36:25 [warn] 25932#0: *1 [kong] some_file.lua:54 hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- If invoked from within a plugin (for example, `key-auth`) it would include the
-- namespace prefix:
--
-- ``` plain
-- 2017/07/09 19:36:25 [warn] 25932#0: *1 [kong] some_file.lua:54 [key-auth] hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- And with metatable, the following call:
--
-- ``` lua
-- kong.log.deprecation("hello ", "world", { after = "2.5.0", removal = "3.0.0" })
-- ```
--
-- would, within the core, produce a log line similar to:
--
-- ``` plain
-- 2017/07/09 19:36:25 [warn] 25932#0: *1 [kong] some_file.lua:54 hello world (deprecated after 2.5.0, scheduled for removal in 3.0.0), client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- @function kong.log.deprecation
-- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
-- @param ... all params will be concatenated and stringified before being sent to the log
--            (if the last param is a table, it is considered as a deprecation metadata)
-- @return Nothing; throws an error on invalid inputs.
--
-- @usage
-- kong.log.deprecation("hello ", "world")
-- kong.log.deprecation("hello ", "world", { after = "2.5.0" })
-- kong.log.deprecation("hello ", "world", { removal = "3.0.0" })
-- kong.log.deprecation("hello ", "world", { after = "2.5.0", removal = "3.0.0" })
-- kong.log.deprecation("hello ", "world", { trace = true })
local new_deprecation do
  local mt = getmetatable(require("kong.deprecation"))
  new_deprecation = function(write)
    return setmetatable({ write = write }, mt)
  end
end


---
-- Like `kong.log()`, this function produces a log with a `notice` level
-- and accepts any number of arguments. If inspect logging is disabled
-- via `kong.log.inspect.off()`, then this function prints nothing, and is
-- aliased to a "NOP" function to save CPU cycles.
--
-- This function differs from `kong.log()` in the sense that arguments will be
-- concatenated with a space(`" "`), and each argument is
-- pretty-printed:
--
-- * Numbers are printed (e.g. `5` -> `"5"`)
-- * Strings are quoted (e.g. `"hi"` -> `'"hi"'`)
-- * Array-like tables are rendered (e.g. `{1,2,3}` -> `"{1, 2, 3}"`)
-- * Dictionary-like tables are rendered on multiple lines
--
-- This function is intended for debugging, and usage
-- in production code paths should be avoided due to the expensive formatting
-- operations it can perform. Existing statements can be left in production code
-- but nopped by calling `kong.log.inspect.off()`.
--
-- When writing logs, `kong.log.inspect()` always uses its own format, defined
-- as:
--
-- ``` plain
-- %file_src:%func_name:%line_src %message
-- ```
--
-- Where:
--
-- * `%file_src`: The filename the log was called from.
-- * `%func_name`: The name of the function the log was called from.
-- * `%line_src`: The line number the log was called from.
-- * `%message`: The message, made of concatenated, pretty-printed arguments
--   given by the caller.
--
-- This function uses the [inspect.lua](https://github.com/kikito/inspect.lua)
-- library to pretty-print its arguments.
--
-- @function kong.log.inspect
-- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
-- @param ... Parameters are concatenated with spaces between them and
-- rendered as described.
-- @usage
-- kong.log.inspect("some value", a_variable)
local new_inspect

do
  local function nop() end


  local _inspect_mt = {
    __call = function(self, ...)
      self.print(...)
    end,
  }


  new_inspect = function(namespace)
    local _INSPECT_FORMAT = _PREFIX .. "%file_src:%func_name:%line_src ["..namespace.."]\n%message"
    local inspect_buf = assert(parse_modifiers(_INSPECT_FORMAT))

    local self = {}


    ---
    -- Enables inspect logs for this logging facility. Calls to
    -- `kong.log.inspect` will be writing log lines with the appropriate
    -- formatting of arguments.
    --
    -- @function kong.log.inspect.on
    -- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
    -- @usage
    -- kong.log.inspect.on()
    function self.on()
      self.print = gen_log_func(_LEVELS.debug, inspect_buf, inspect, 3, " ")
    end


    ---
    -- Disables inspect logs for this logging facility. All calls to
    -- `kong.log.inspect()` will be nopped.
    --
    -- @function kong.log.inspect.off
    -- @phases init_worker, certificate, rewrite, access, header_filter, response, body_filter, log
    -- @usage
    -- kong.log.inspect.off()
    function self.off()
      self.print = nop
    end


    self.on()


    return setmetatable(self, _inspect_mt)
  end
end


local _log_mt = {
  __call = function(self, ...)
    return self.notice(...)
  end,
}


local function get_default_serialize_values()
  if ngx.config.subsystem == "http" then
    return {
      { key = "request.headers.authorization", value = "REDACTED", mode = "replace" },
      { key = "request.headers.proxy-authorization", value = "REDACTED", mode = "replace" },
    }
  end

  return {}
end

---
-- Sets a value to be used on the `serialize` custom table.
--
-- Logging plugins use the output of `kong.log.serialize()` as a base for their logs.
-- This function lets you customize the log output.
--
-- It can be used to replace existing values in the output, or to delete
-- existing values by passing `nil`.
--
-- **Note:** The type-checking of the `value` parameter can take some time, so
-- it is deferred to the `serialize()` call, which happens in the log
-- phase in most real-usage cases.
--
-- @function kong.log.set_serialize_value
-- @phases certificate, rewrite, access, header_filter, response, body_filter, log
-- @tparam string key The name of the field.
-- @tparam number|string|boolean|table value Value to be set. When a table is used, its keys must be numbers, strings, or booleans, and its values can be numbers, strings, or other tables like itself, recursively.
-- @tparam table options Can contain two entries: options.mode can be `set` (the default, always sets), `add` (only add if entry does not already exist) and `replace` (only change value if it already exists).
-- @treturn table The request information table.
-- @usage
-- -- Adds a new value to the serialized table
-- kong.log.set_serialize_value("my_new_value", 1)
-- assert(kong.log.serialize().my_new_value == 1)
--
-- -- Value can be a table
-- kong.log.set_serialize_value("my", { new = { value = 2 } })
-- assert(kong.log.serialize().my.new.value == 2)
--
-- -- It is possible to change an existing serialized value
-- kong.log.set_serialize_value("my_new_value", 3)
-- assert(kong.log.serialize().my_new_value == 3)
--
-- -- Unset an existing value by setting it to nil
-- kong.log.set_serialize_value("my_new_value", nil)
-- assert(kong.log.serialize().my_new_value == nil)
--
-- -- Dots in the key are interpreted as table accesses
-- kong.log.set_serialize_value("my.new.value", 4)
-- assert(kong.log.serialize().my.new_value == 4)
--
local function set_serialize_value(key, value, options)
  check_phase(phases_with_ctx)

  options = options or {}
  local mode = options.mode or "set"

  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  if mode ~= "set" and mode ~= "add" and mode ~= "replace" then
    error("mode must be 'set', 'add' or 'replace'", 2)
  end

  local ongx = options.ngx or ngx
  local ctx = ongx.ctx
  ctx.serialize_values = ctx.serialize_values or get_default_serialize_values()
  ctx.serialize_values[#ctx.serialize_values + 1] =
    { key = key, value = value, mode = mode }
end


local serialize
do
  local function is_valid_value(v, visited)
    local t = type(v)
    if v == nil or t == "number" or t == "string" or t == "boolean" then
      return true
    end

    if t ~= "table" then
      return false
    end

    if visited[v] then
      return false
    end
    visited[v] = true

    for k, val in pairs(v) do
      t = type(k)
      if (t ~= "string"
          and t ~= "number"
          and t ~= "boolean")
        or not is_valid_value(val, visited)
      then
        return false
      end
    end

    return true
  end

  -- Modify returned table with values set with kong.log.set_serialize_values
  local function edit_result(ctx, root)
    local serialize_values = ctx.serialize_values or get_default_serialize_values()
    local key, mode, new_value, subkeys, node, subkey, last_subkey, existing_value
    for _, item in ipairs(serialize_values) do
      key, mode, new_value = item.key, item.mode, item.value

      if not is_valid_value(new_value, {}) then
        error("value must be nil, a number, string, boolean or a non-self-referencial table containing numbers, string and booleans", 2)
      end

      -- Split key by ., creating subtables when needed
      subkeys = setmetatable(split(key, "."), nil)
      node = root -- start in root, iterate with each subkey
      for i = 1, #subkeys - 1 do -- note that last subkey is treated differently, below
        subkey = subkeys[i]
        if node[subkey] == nil then
          if mode == "set" or mode == "add" then
            node[subkey] = {} -- add subtables as needed
          else
            node = nil
            break -- mode == replace; and we have a missing link on the "chain"
          end
        end

        if type(node[subkey]) ~= "table" then
          error("The key '" .. key .. "' could not be used as a serialize value. " ..
                "Subkey '" .. subkey .. "' is not a table. It's " .. tostring(node[subkey]))
        end

        node = node[subkey]
      end
      if type(node) == "table" then
        last_subkey = subkeys[#subkeys]
        existing_value = node[last_subkey]
        if (mode == "set")
        or (mode == "add" and existing_value == nil)
        or (mode == "replace" and existing_value ~= nil)
        then
          node[last_subkey] = new_value
        end
      end
    end

    return root
  end

  local function build_authenticated_entity(ctx)
    local authenticated_entity
    if ctx.authenticated_credential ~= nil then
      authenticated_entity = {
        id = ctx.authenticated_credential.id,
        consumer_id = ctx.authenticated_credential.consumer_id,
      }
    end

    return authenticated_entity
  end

  local function build_tls_info(var, override)
    local tls_info
    local tls_info_ver = ngx_ssl.get_tls1_version_str()
    if tls_info_ver then
      tls_info = {
        version = tls_info_ver,
        cipher = var.ssl_cipher,
        client_verify = override or var.ssl_client_verify,
      }
    end

    return tls_info
  end

  local function to_decimal(str)
    local n = tonumber(str, 10)
    return n or str
  end

  ---
  -- Generates a table with useful information for logging.
  --
  -- This method can be used in the `http` subsystem.
  --
  -- The following fields are included in the returned table:
  -- * `client_ip` - client IP address in textual format.
  -- * `latencies` - request/proxy latencies.
  -- * `request.id` - request id.
  -- * `request.headers` - request headers.
  -- * `request.method` - request method.
  -- * `request.querystring` - request query strings.
  -- * `request.size` - size of request.
  -- * `request.url` and `request.uri` - URL and URI of request.
  -- * `response.headers` - response headers.
  -- * `response.size` - size of response.
  -- * `response.status` - response HTTP status code.
  -- * `route` - route object matched.
  -- * `service` - service object used.
  -- * `started_at` - timestamp this request came in, in milliseconds.
  -- * `tries` - Upstream information; this is an array and if any balancer retries occurred, will contain more than one entry.
  -- * `upstream_uri` - request URI sent to Upstream.
  --
  -- The following fields are only present in an authenticated request (with consumer):
  --
  -- * `authenticated_entity` - credential used for authentication.
  -- * `consumer` - consumer entity accessing the resource.
  --
  -- The following fields are only present in a TLS/HTTPS request:
  -- * `request.tls.version` - TLS/SSL version used by the connection.
  -- * `request.tls.cipher` - TLS/SSL cipher used by the connection.
  -- * `request.tls.client_verify` - mTLS validation result. Contents are the same as described in [$ssl_client_verify](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#var_ssl_client_verify).
  --
  -- The following field is only present in requests where a tracing plugin (OpenTelemetry or Zipkin) is executed:
  -- * `trace_id` - trace ID.
  --
  -- The following field is only present in requests where the Correlation ID plugin is executed:
  -- * `correlation_id` - correlation ID.
  --
  -- **Warning:** This function may return sensitive data (e.g., API keys).
  -- Consider filtering before writing it to unsecured locations.
  --
  -- All fields in the returned table may be altered using `kong.log.set_serialize_value`.
  --
  -- The following HTTP authentication headers are redacted by default, if they appear in the request:
  -- * `request.headers.authorization`
  -- * `request.headers.proxy-authorization`
  --
  -- To see what content is present in your setup, enable any of the logging
  -- plugins (e.g., `file-log`) and the output written to the log file is the table
  -- returned by this function JSON-encoded.
  --
  -- @function kong.log.serialize
  -- @phases log
  -- @treturn table the request information table
  -- @usage
  -- kong.log.serialize()

  if ngx.config.subsystem == "http" then
    function serialize(options)
      check_phase(PHASES_LOG)

      options = options or {}
      local ongx = options.ngx or ngx
      local okong = options.kong or kong

      local ctx = ongx.ctx
      local var = ongx.var

      local request_uri = var.request_uri or ""

      local host_port = ctx.host_port or var.server_port

      local upstream_uri = var.upstream_uri or ""
      if upstream_uri ~= "" and not find(upstream_uri, "?", nil, true) then
        if byte(ctx.request_uri or var.request_uri, -1) == QUESTION_MARK then
          upstream_uri = upstream_uri .. "?"
        elseif var.is_args == "?" then
          upstream_uri = upstream_uri .. "?" .. (var.args or "")
        end
      end

      -- The value of upstream_status is a string, and status codes may be
      -- seperated by comma or grouped by colon, according to
      -- the nginx doc: http://nginx.org/en/docs/http/ngx_http_upstream_module.html#upstream_status
      local upstream_status = var.upstream_status or ""

      local response_source = okong.response.get_source(ongx.ctx)
      local response_source_name = TYPE_NAMES[response_source]

      local root = {
        request = {
          id = request_id_get() or "",
          uri = request_uri,
          url = var.scheme .. "://" .. var.host .. ":" .. host_port .. request_uri,
          querystring = okong.request.get_query(), -- parameters, as a table
          method = okong.request.get_method(), -- http method
          headers = okong.request.get_headers(),
          size = to_decimal(var.request_length),
          tls = build_tls_info(var, ctx.CLIENT_VERIFY_OVERRIDE),
        },
        upstream_uri = upstream_uri,
        upstream_status = upstream_status,
        response = {
          status = ongx.status,
          headers = ongx.resp.get_headers(),
          size = to_decimal(var.bytes_sent),
        },
        latencies = {
          kong = (ctx.KONG_PROXY_LATENCY or ctx.KONG_RESPONSE_LATENCY or 0) +
                 (ctx.KONG_RECEIVE_TIME or 0),
          proxy = ctx.KONG_WAITING_TIME or -1,
          request = tonumber(var.request_time) * 1000,
        },
        tries = (ctx.balancer_data or {}).tries,
        authenticated_entity = build_authenticated_entity(ctx),
        route = cycle_aware_deep_copy(ctx.route),
        service = cycle_aware_deep_copy(ctx.service),
        consumer = cycle_aware_deep_copy(ctx.authenticated_consumer),
        client_ip = var.remote_addr,
        started_at = okong.request.get_start_time(),
        source = response_source_name,
      }

      return edit_result(ctx, root)
    end

  else
    function serialize(options)
      check_phase(PHASES_LOG)

      options = options or {}
      local ongx = options.ngx or ngx
      local okong = options.kong or kong

      local ctx = ongx.ctx
      local var = ongx.var

      local host_port = ctx.host_port or var.server_port

      local root = {
        session = {
          tls = build_tls_info(var, ctx.CLIENT_VERIFY_OVERRIDE),
          received = to_decimal(var.bytes_received),
          sent = to_decimal(var.bytes_sent),
          status = ongx.status,
          server_port = to_decimal(host_port),
        },
        upstream = {
          received = to_decimal(var.upstream_bytes_received),
          sent = to_decimal(var.upstream_bytes_sent),
        },
        latencies = {
          kong = ctx.KONG_PROXY_LATENCY or ctx.KONG_RESPONSE_LATENCY or 0,
          session = var.session_time * 1000,
        },
        tries = (ctx.balancer_data or {}).tries,
        authenticated_entity = build_authenticated_entity(ctx),
        route = cycle_aware_deep_copy(ctx.route),
        service = cycle_aware_deep_copy(ctx.service),
        consumer = cycle_aware_deep_copy(ctx.authenticated_consumer),
        client_ip = var.remote_addr,
        started_at = okong.request.get_start_time(),
      }

      return edit_result(ctx, root)
    end
  end
end


local function new_log(namespace, format)
  if type(namespace) ~= "string" then
    error("namespace must be a string", 2)
  end

  if namespace == "" then
    error("namespace cannot be an empty string", 2)
  end

  if format then
    if type(format) ~= "string" then
      error("format must be a string if specified", 2)
    end

    if format == "" then
      error("format cannot be an empty string if specified", 2)
    end
  end

  local self = {}


  function self.set_format(fmt)
    if fmt and type(fmt) ~= "string" then
      error("format must be a string", 2)

    elseif not fmt then
      fmt = _DEFAULT_NAMESPACED_FORMAT
    end

    -- pre-compile namespace into format
    local format = _PREFIX .. fmt:gsub("([^%%])%%namespace", "%1" .. namespace)

    local buf, err = parse_modifiers(format)
    if not buf then
      error(err, 2)
    end

    for log_lvl_name, log_lvl in pairs(_LEVELS) do
      self[log_lvl_name] = gen_log_func(log_lvl, buf)
    end

    self.deprecation = new_deprecation(gen_log_func(_LEVELS.warn, buf, nil, 5))
  end

  self.set_format(format)

  self.inspect = new_inspect(namespace)

  self.set_serialize_value = set_serialize_value
  self.serialize = serialize

  return setmetatable(self, _log_mt)
end


_log_mt.__index = _log_mt
_log_mt.new = new_log


return {
  new = function()
    return new_log("core", _DEFAULT_FORMAT)
  end,
}
