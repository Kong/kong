local say = require "say"
local luassert = require "luassert.assert"
local pretty = require "pl.pretty"

local fmt = string.format
local insert = table.insert

local E_ARG_COUNT = "assertion.internal.argtolittle"
local E_ARG_TYPE = "assertion.internal.badargtype"


---@alias spec.helpers.wait.ctx.result
---| "timeout"
---| "error"
---| "success"
---| "max tries"

local TIMEOUT   = "timeout"
local ERROR     = "error"
local SUCCESS   = "success"
local MAX_TRIES = "max tries"


---@alias spec.helpers.wait.ctx.condition
---| "truthy"
---| "falsy"
---| "error"
---| "no_error"


--- helper functions that check the result of pcall() and report if the
--- wait ctx condition has been met
---
---@type table<spec.helpers.wait.ctx.condition, fun(boolean, any):boolean>
local COND = {
  truthy = function(pok, ok_or_err)
    return (pok and ok_or_err and true) or false
  end,

  falsy = function(pok, ok_or_err)
    return (pok and not ok_or_err) or false
  end,

  error = function(pok)
    return not pok
  end,

  no_error = function(pok)
    return (pok and true) or false
  end,
}


---@param ... any
---@return any
local function first_non_nil(...)
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    if v ~= nil then
      return v
    end
  end
end


---@param exp_type string
---@param field string|integer
---@param value any
---@param caller? string
---@param level? integer
---@return any
local function check_type(exp_type, field, value, caller, level)
  caller = caller or "wait_until"
  level = (level or 1) + 1

  local got_type = type(value)

  -- accept callable tables
  if exp_type == "function"
  and got_type == "table"
  and type(debug.getmetatable(value)) == "table"
  and type(debug.getmetatable(value).__call) == "function"
  then
    got_type = "function"
  end

  if got_type ~= exp_type then
    error(say(E_ARG_TYPE, { field, caller, exp_type, type(value) }),
          level)
  end

  return value
end


local DEFAULTS = {
  timeout           = 5,
  step              = 0.05,
  message           = "UNSPECIFIED",
  max_tries         = 0,
  ignore_exceptions = false,
  condition         = "truthy",
}


---@class spec.helpers.wait.ctx
---
---@field condition           "truthy"|"falsy"|"error"|"no_error"
---@field condition_met       boolean
---@field debug?              boolean
---@field elapsed             number
---@field last_raised_error   any
---@field error_raised        boolean
---@field fn                  function
---@field ignore_exceptions   boolean
---@field last_returned_error any
---@field last_returned_value any
---@field last_error          any
---@field message?            string
---@field result              spec.helpers.wait.ctx.result
---@field step                number
---@field timeout             number
---@field tries               number
local wait_ctx = {
  condition           = nil,
  condition_met       = false,
  debug               = nil,
  elapsed             = 0,
  error               = nil,
  error_raised        = false,
  ignore_exceptions   = nil,
  last_returned_error = nil,
  last_returned_value = nil,
  max_tries           = nil,
  message             = nil,
  result              = "timeout",
  step                = nil,
  timeout             = nil,
  tries               = 0,
}


local wait_ctx_mt = { __index = wait_ctx }

function wait_ctx:dd(msg)
  if self.debug then
    print(fmt("\n\n%s\n\n", pretty.write(msg)))
  end
end


function wait_ctx:wait()
  ngx.update_time()

  local tstart = ngx.now()
  local texp = tstart + self.timeout
  local ok, res, err

  local is_met = COND[self.condition]

  if self.condition == "no_error" then
    self.ignore_exceptions = true
  end

  local tries_remain = self.max_tries

  local f = self.fn

  while true do
    ok, res, err = pcall(f)

    self.tries = self.tries + 1
    tries_remain = tries_remain - 1

    self.condition_met = is_met(ok, res)

    self:dd(self)

    -- yay!
    if self.condition_met then
      self.last_returned_value = res
      self.result = SUCCESS
      break

      -- non-truthy return value
    elseif ok and not res then
      self.last_returned_error = first_non_nil(err, self.last_returned_error)
      self.last_error = self.last_returned_error

      -- error()
    else
      self.error_raised = true
      self.last_raised_error = first_non_nil(res, "UNKNOWN")
      self.last_error = self.last_raised_error

      if not self.ignore_exceptions then
        self.result = ERROR
        break
      end
    end

    if tries_remain == 0 then
      self.result = MAX_TRIES
      break
    end

    ngx.update_time()

    if ngx.now() >= texp then
      self.result = TIMEOUT
      break
    end

    ngx.sleep(self.step)
  end

  ngx.update_time()
  self.elapsed = ngx.now() - tstart

  self:dd(self)

  -- re-raise
  if self.error_raised and not self.ignore_exceptions then
    error(self.last_raised_error, 2)
  end
end


local CTX_TYPES = {
  condition         = "string",
  fn                = "function",
  max_tries         = "number",
  timeout           = "number",
  message           = "string",
  step              = "number",
  ignore_exceptions = "boolean",
}


function wait_ctx:validate(key, value, caller, level)
  local typ = CTX_TYPES[key]

  if not typ then
    -- we don't care about validating this key
    return value
  end

  if key == "condition" and type(value) == "string" then
    assert(COND[value] ~= nil,
           say(E_ARG_TYPE, { "condition", caller or "wait_until",
                           "one of: 'truthy', 'falsy', 'error', 'no_error'",
                           value }), level + 1)
  end


  return check_type(typ, key, value, caller, level)
end


---@param state table
---@return spec.helpers.wait.ctx
local function get_or_create_ctx(state)
  local ctx = rawget(state, "wait_ctx")

  if not ctx then
    ctx = setmetatable({}, wait_ctx_mt)
    rawset(state, "wait_ctx", ctx)
  end

  return ctx
end


---@param ctx spec.helpers.wait.ctx
---@param key string
---@param ... any
local function param(ctx, key, ...)
  local value = first_non_nil(first_non_nil(...), DEFAULTS[key])
  ctx[key] = ctx:validate(key, value, "wait_until", 3)
end


---@param  state     table
---@param  arguments table
---@param  level     integer
---@return boolean   ok
---@return table     return_values
local function wait_until(state, arguments, level)
  assert(arguments.n > 0,
         say(E_ARG_COUNT, { "wait_until", 1, arguments.n }),
         level + 1)

  local input = check_type("table", 1, arguments[1])
  local ctx = get_or_create_ctx(state)

  param(ctx, "fn",                input.fn)
  param(ctx, "timeout",           input.timeout)
  param(ctx, "step",              input.step)
  param(ctx, "message",           input.message, arguments[2])
  param(ctx, "max_tries",         input.max_tries)
  param(ctx, "debug",             input.debug, ctx.debug, false)
  param(ctx, "condition",         input.condition)
  param(ctx, "ignore_exceptions", input.ignore_exceptions)

  -- reset the state
  rawset(state, "wait_ctx", nil)

  ctx:wait()

  if ctx.condition_met then
    return true, { ctx.last_returned_value, n = 1 }
  end

  local errors = {}
  local result
  if ctx.result == ERROR then
    result = "error() raised"

  elseif ctx.result == MAX_TRIES then
    result = ("max tries (%s) reached"):format(ctx.max_tries)

  elseif ctx.result == TIMEOUT then
    result = ("timed out after %ss"):format(ctx.elapsed)
  end

  if ctx.last_raised_error then
    insert(errors, "Last raised error:")
    insert(errors, "")
    insert(errors, pretty.write(ctx.last_raised_error))
    insert(errors, "")
  end

  if ctx.last_returned_error then
    insert(errors, "Last returned error:")
    insert(errors, "")
    insert(errors, pretty.write(ctx.last_returned_error))
    insert(errors, "")
  end

  arguments[1] = ctx.message
  arguments[2] = result
  arguments[3] = table.concat(errors, "\n")
  arguments[4] = ctx.timeout
  arguments[5] = ctx.step
  arguments[6] = ctx.elapsed
  arguments[7] = ctx.tries
  arguments[8] = ctx.error_raised
  arguments.n = 8

  arguments.nofmt = {}
  for i = 1, arguments.n do
    arguments.nofmt[i] = true
  end

  return false, { ctx.last_error, n = 1 }
end


say:set("assertion.wait_until.failed", [[
Failed to assert eventual condition:

%q

Result: %s

%s
---

Timeout  = %s
Step     = %s
Elapsed  = %s
Tries    = %s
Raised   = %s
]])

luassert:register("assertion", "wait_until", wait_until,
                  "assertion.wait_until.failed")


local function wait_until_modifier(key)
  return function(state, arguments)
    local ctx = get_or_create_ctx(state)
    ctx[key] = ctx:validate(key, arguments[1], key, 1)

    return state
  end
end

luassert:register("modifier", "with_timeout",
                  wait_until_modifier("timeout"))

luassert:register("modifier", "with_step",
                  wait_until_modifier("step"))

luassert:register("modifier", "with_max_tries",
                  wait_until_modifier("max_tries"))

-- luassert blows up on us if we try to use 'error' or 'errors'
luassert:register("modifier", "ignore_exceptions",
                  wait_until_modifier("ignore_exceptions"))


---@param ctx spec.helpers.wait.ctx
local function ctx_builder(ctx)
  local self = setmetatable({}, {
    __index = function(_, key)
      error("unknown modifier/assertion: " .. tostring(key), 2)
     end
  })

  local function with(field)
    return function(value)
      ctx[field] = ctx:validate(field, value, "with_" .. field, 2)
      return self
    end
  end

  self.with_timeout = with("timeout")
  self.with_step = with("step")
  self.with_max_tries = with("max_tries")

  self.ignore_exceptions = function(ignore)
    ctx.ignore_exceptions = ctx:validate("ignore_exceptions", ignore,
                                         "ignore_exceptions", 2)
    return self
  end

  self.is_truthy = function(msg)
    ctx.condition = "truthy"
    return luassert.wait_until(ctx, msg)
  end

  self.is_falsy = function(msg)
    ctx.condition = "falsy"
    return luassert.wait_until(ctx, msg)
  end

  self.has_error = function(msg)
    ctx.condition = "error"
    return luassert.wait_until(ctx, msg)
  end

  self.has_no_error = function(msg)
    ctx.condition = "no_error"
    return luassert.wait_until(ctx, msg)
  end

  return self
end


local function eventually(state, arguments)
  local ctx = get_or_create_ctx(state)

  ctx.fn = first_non_nil(arguments[1], ctx.fn)

  check_type("function", 1, ctx.fn, "eventually")

  arguments[1] = ctx_builder(ctx)
  arguments.n = 1

  return true, arguments
end

luassert:register("assertion", "eventually", eventually)
