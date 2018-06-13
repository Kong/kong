local errlog = require "ngx.errlog"
local ngx_re = require "ngx.re"


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
    buf[1] = to_string(select(1, ...))
  end,

  [2] = function(buf, to_string, ...)
    buf[1] = to_string(select(1, ...))
    buf[2] = to_string(select(2, ...))
  end,

  [3] = function(buf, to_string, ...)
    buf[1] = to_string(select(1, ...))
    buf[2] = to_string(select(2, ...))
    buf[3] = to_string(select(3, ...))
  end,

  [4] = function(buf, to_string, ...)
    buf[1] = to_string(select(1, ...))
    buf[2] = to_string(select(2, ...))
    buf[3] = to_string(select(3, ...))
    buf[4] = to_string(select(4, ...))
  end,

  [5] = function(buf, to_string, ...)
    buf[1] = to_string(select(1, ...))
    buf[2] = to_string(select(2, ...))
    buf[3] = to_string(select(3, ...))
    buf[4] = to_string(select(4, ...))
    buf[5] = to_string(select(5, ...))
  end,
}


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
        variadic_buf[i] = to_string(select(i, ...))
      end
    end

    local msg = concat(variadic_buf, sep, 1, n)

    for i = 1, imm_buf.n_messages do
      imm_buf[imm_buf.message_idxs[i]] = msg
    end

    --errlog.raw_log(lvl_const, concat(imm_buf, nil, 1, imm_buf.n_len))
    ngx.log(lvl_const, concat(imm_buf, nil, 1, imm_buf.n_len))
  end
end


local new_inspect

do
  local inspect = require "inspect"


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

    function self.on()
      self.print = gen_log_func(_LEVELS.notice, inspect_buf, inspect, 3, " ")
    end

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
