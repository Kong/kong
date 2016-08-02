--
-- 参数校验拦截器
-- -- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local response, _ = require "kong.yop.response"()
local next = next
local pairs = pairs
local stringy = require "stringy"
local tonumber = tonumber
local ngxMatch = ngx.re.match
local _M = {}

local function validateNull(p) if p.value == nil then response.validateNullException(p) end end

local function validateBlank(p) if p.value == nil or stringy.strip(p.value) == '' then response.validateBlankException(p) end end

local function validateEmail(p)
  if p.value ~= nil and not p.value:match("^[A-Za-z0-9%.]+@[%a%d]+%.[%a%d]+$") then response.validateEmailException(p) end
end

local function validateMobile(p) if p.value ~= nil and not p.value:match("^1[3|4|5|8|7]%d%d%d%d%d%d%d%d%d$") then response.validateMobileException(p) end end

local function validateLength(p, rule)
  if p.value == nil then return end
  if rule.min ~= nil and #p.value < rule.min then response.validateLengthLessException(p, rule) end
  if rule.max ~= nil and #p.value > rule.max then response.validateLengthMoreException(p, rule) end
end

local function validateRange(p, rule)
  if p.value == nil then return end
  local pn = tonumber(p.value)
  if pn == nil then return false end
  if rule.min ~= nil and pn < rule.min then response.validateRangeLessException(p, rule) end
  if rule.max ~= nil and pn > rule.max then response.validateRangeMoreException(p, rule) end
end

local function validateInt(p)
  if p.value ~= nil and not p.value:match("^[-+]?[%d]*$") then response.validateIntException(p) end
end

local function validatePattern(p, rule)
  local value = p.value
  if value == nil then return end
  local matchResult = ngxMatch(value, rule, "o")
  if matchResult == nil or matchResult[0] ~= value then
    response.validatePatternException(p, rule)
  end
end

local validators = {
  NotNull = validateNull,
  NotBlank = validateBlank,
  Email = validateEmail,
  Mobile = validateMobile,
  Length = validateLength,
  Range = validateRange,
  MatchPattern = validatePattern,
  RequireInt = validateInt,
  URL = function() end --这个正则太jb费劲了
}

_M.process = function(ctx)
  local validator = ctx.validator
  local appKey = ctx.appKey
  local parameters = ctx.parameters

  if validator == nil or next(validator) == nil then return end

  for name, value in pairs(validator) do
    for validator, rule in pairs(value) do
      validators[validator]({ app = appKey, name = name, value = parameters[name] }, rule)
    end
  end
end

return _M
