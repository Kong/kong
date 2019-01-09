---
-- This namespace contains an instance of a "logging facility", which is a
-- table containing all of the methods described below.
--
-- This instance is namespaced per plugin, and Kong will make sure that before
-- executing a plugin, it will swap this instance with a logging facility
-- dedicated to the plugin. This allows the logs to be prefixed with the
-- plugin's name for debugging purposes.
--
-- @module kong.log


local errlog = require "ngx.errlog"
local ngx_re = require "ngx.re"
local inspect = require "inspect"


local sub = string.sub
local type = type
local find = string.find
local select = select
local concat = table.concat
local getinfo = debug.getinfo
local reverse = string.reverse
local tostring = tostring
local setmetatable = setmetatable


local _PREFIX = "[kong] "
local _DEFAULT_FORMAT = "%file_src:%line_src %message"
local _DEFAULT_NAMESPACED_FORMAT = "%file_src:%line_src [%namespace] %message"


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
        table.insert(buf.message_idxs, i)

      else
        buf.debug_flags = (buf.debug_flags or "") .. mod.flag

        buf.modifiers = buf.modifiers or {}
        table.insert(buf.modifiers, {
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
  [1] = function(buf, to_string, ...)
    buf[1] = to_string((select(1, ...)))
  end,

  [2] = function(buf, to_string, ...)
    buf[1] = to_string((select(1, ...)))
    buf[2] = to_string((select(2, ...)))
  end,

  [3] = function(buf, to_string, ...)
    buf[1] = to_string((select(1, ...)))
    buf[2] = to_string((select(2, ...)))
    buf[3] = to_string((select(3, ...)))
  end,

  [4] = function(buf, to_string, ...)
    buf[1] = to_string((select(1, ...)))
    buf[2] = to_string((select(2, ...)))
    buf[3] = to_string((select(3, ...)))
    buf[4] = to_string((select(4, ...)))
  end,

  [5] = function(buf, to_string, ...)
    buf[1] = to_string((select(1, ...)))
    buf[2] = to_string((select(2, ...)))
    buf[3] = to_string((select(3, ...)))
    buf[4] = to_string((select(4, ...)))
    buf[5] = to_string((select(5, ...)))
  end,
}


--- Write a log line to the location specified by the current Nginx
-- configuration block's `error_log` directive, with the `notice` level (similar
-- to `print()`).
--
-- The Nginx `error_log` directive is set via the `log_level`, `proxy_error_log`
-- and `admin_error_log` Kong configuration properties.
--
-- Arguments given to this function will be concatenated similarly to
-- `ngx.log()`, and the log line will report the Lua file and line number from
-- which it was invoked. Unlike `ngx.log()`, this function will prefix error
-- messages with `[kong]` instead of `[lua]`.
--
-- Arguments given to this function can be of any type, but table arguments
-- will be converted to strings via `tostring` (thus potentially calling a
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
-- * `%namespace`: is the configured namespace (the plugin name in this case).
-- * `%file_src`: is the file name from where the log was called from.
-- * `%line_src`: is the line number from where the log was called from.
-- * `%message`: is the message, made of concatenated arguments given by the caller.
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
-- If invoked from within a plugin (e.g. `key-auth`) it would include the
-- namespace prefix, like so:
--
-- ``` plain
-- 2017/07/09 19:36:25 [notice] 25932#0: *1 [kong] some_file.lua:54 [key-auth] hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- @function kong.log
-- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
-- @param ... all params will be concatenated and stringified before being sent to the log
-- @return Nothing; throws an error on invalid inputs.
--
-- @usage
-- kong.log("hello ", "world") -- alias to kong.log.notice()

---
-- Similar to `kong.log()`, but the produced log will have the severity given by
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
-- If invoked from within a plugin (e.g. `key-auth`) it would include the
-- namespace prefix, like so:
--
-- ``` plain
-- 2017/07/09 19:36:25 [error] 25932#0: *1 [kong] some_file.lua:54 [key-auth] hello world, client: 127.0.0.1, server: localhost, request: "GET /log HTTP/1.1", host: "localhost"
-- ```
--
-- @function kong.log.LEVEL
-- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
-- @param ... all params will be concatenated and stringified before being sent to the log
-- @return Nothing; throws an error on invalid inputs.
-- @usage
-- kong.log.warn("something require attention")
-- kong.log.err("something failed: ", err)
-- kong.log.alert("something requires immediate action")
local function gen_log_func(lvl_const, imm_buf, to_string, stack_level, sep)
  to_string = to_string or tostring
  stack_level = stack_level or 2

  local sys_log_level
  local variadic_buf = {}

  return function(...)
    if not sys_log_level and ngx.get_phase() ~= "init" then
      -- only grab sys_log_level after init_by_lua, where it is
      -- hard-coded
      sys_log_level = errlog.get_sys_filter_level()
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
      serializers[n](variadic_buf, to_string, ...)

    else
      for i = 1, n do
        variadic_buf[i] = to_string((select(i, ...)))
      end
    end

    local msg = concat(variadic_buf, sep, 1, n)

    for i = 1, imm_buf.n_messages do
      imm_buf[imm_buf.message_idxs[i]] = msg
    end

    local fullmsg = concat(imm_buf, nil, 1, imm_buf.n_len)

    if to_string == inspect then
      local fullmsg_len = #fullmsg
      local WRAP = 120

      if fullmsg:find("\n", 1, true) or fullmsg_len > WRAP then
        local i = 1

        errlog.raw_log(lvl_const, "+" .. ("-"):rep(WRAP) .. "+")

        while i <= fullmsg_len do
          local part = string.sub(fullmsg, i, i + WRAP - 1)
          local nl = part:match("()\n")

          if nl then
            part = string.sub(fullmsg, i, i + nl - 2)
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
    end

    errlog.raw_log(lvl_const, fullmsg)
  end
end


---
-- Like `kong.log()`, this function will produce a log with the `notice` level,
-- and accepts any number of arguments as well. If inspect logging is disabled
-- via `kong.log.inspect.off()`, then this function prints nothing, and is
-- aliased to a "NOP" function in order to save CPU cycles.
--
-- ``` lua
-- kong.log.inspect("...")
-- ```
--
-- This function differs from `kong.log()` in the sense that arguments will be
-- concatenated with a space(`" "`), and each argument will be
-- "pretty-printed":
--
-- * numbers will printed (e.g. `5` -> `"5"`)
-- * strings will be quoted (e.g. `"hi"` -> `'"hi"'`)
-- * array-like tables will be rendered (e.g. `{1,2,3}` -> `"{1, 2, 3}"`)
-- * dictionary-like tables will be rendered on multiple lines
--
-- This function is intended for use with debugging purposes in mind, and usage
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
-- * `%file_src`: is the file name from where the log was called from.
-- * `%func_name`: is the name of the function from where the log was called
--   from.
-- * `%line_src`: is the line number from where the log was called from.
-- * `%message`: is the message, made of concatenated, pretty-printed arguments
--   given by the caller.
--
-- This function uses the [inspect.lua](https://github.com/kikito/inspect.lua)
-- library to pretty-print its arguments.
--
-- @function kong.log.inspect
-- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
-- @param ... Parameters will be concatenated with spaces between them and
-- rendered as described
-- @usage
-- kong.log.inspect("some value", a_variable)
local new_inspect

do
  local _INSPECT_FORMAT = _PREFIX .. "%file_src:%func_name:%line_src %message"
  local inspect_buf = assert(parse_modifiers(_INSPECT_FORMAT))
  local function nop() end


  local _inspect_mt = {
    __call = function(self, ...)
      self.print(...)
    end,
  }


  new_inspect = function(format)
    local self = {}


    ---
    -- Enables inspect logs for this logging facility. Calls to
    -- `kong.log.inspect` will be writing log lines with the appropriate
    -- formatting of arguments.
    --
    -- @function kong.log.inspect.on
    -- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
    -- @usage
    -- kong.log.inspect.on()
    function self.on()
      self.print = gen_log_func(_LEVELS.notice, inspect_buf, inspect, 3, " ")
    end


    ---
    -- Disables inspect logs for this logging facility. All calls to
    -- `kong.log.inspect()` will be nopped.
    --
    -- @function kong.log.inspect.off
    -- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
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
  end


  self.set_format(format)

  self.inspect = new_inspect(format)

  return setmetatable(self, _log_mt)
end


_log_mt.__index = _log_mt
_log_mt.new = new_log


return {
  new = function()
    return new_log("core", _DEFAULT_FORMAT)
  end,
}
