local BasePlugin = require "kong.plugins.base_plugin"
local req_get_uri_args = ngx.req.get_uri_args
local req_get_method = ngx.req.get_method
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local ngx_decode_args = ngx.decode_args
local response, _ = require "kong.yop.response"()
local json = require "cjson"

local function decode_args(body) if body then return ngx_decode_args(body) end return {} end

local function validateNull(p) if p.value == nil then response.validateNullException(p) end end

local function validateBlank(p) if p.value == nil or (not not tostring(p.value):find("^%s*$")) then response.validateBlankException(p) end end

local function validateEmail(p)
  if p.value ~= nil and not p.value:match("^[A-Za-z0-9%.]+@[%a%d]+%.[%a%d]+$") then response.validateEmailException(p) end
end

local function validateMobile(p) if p.value ~= nil and not p.value:match("^1[3|4|5|8|7]%d%d%d%d%d%d%d%d%d$") then response.validateMobileException(p) end end

local function validateLength(p, rule)
  if p.value == nil then return end
  if rule.min ~= nil and #p.value < rule.min then response.validateLengthLessException(p,rule) end
  if rule.max ~= nil and #p.value > rule.max then response.validateLengthMoreException(p,rule) end
end

local function validateRange(p, rule)
  if p.value == nil then return end
  local pn = tonumber(p.value)
  if pn == nil then return false end
  if rule.min ~= nil and pn < rule.min then response.validateRangeLessException(p,rule) end
  if rule.max ~= nil and pn > rule.max then response.validateRangeMoreException(p,rule) end
end

local function validateInt(p)
  if p.value ~= nil and not p.value:match("^[-+]?[%d]*$") then response.validateIntException(p) end
end

local validators = {
  NotNull = validateNull,
  NotBlank = validateBlank,
  Email = validateEmail,
  Mobile = validateMobile,
  Length = validateLength,
  Range = validateRange,
  MatchPattern = function() end, --java正则跟lua正则不兼容，先都通过
  RequireInt = validateInt,
  URL = function() end --这个正则太jb费劲了
}


local RequestValidatorHandler = BasePlugin:extend()

function RequestValidatorHandler:new() RequestValidatorHandler.super.new(self, "request-validator") end

function RequestValidatorHandler:access(conf)
  RequestValidatorHandler.super.access(self)

  local x = http_client.post("http://localhost:8054/yop-hessian/app", { appKey = "yop-boss" }, { ['accept'] = "application/json" })
  local o = json.decode(x)
  ngx.log(ngx.INFO,o.status)

  if not conf.validator then return end
  local parameters;
  if req_get_method() == 'GET' then parameters = req_get_uri_args() else req_read_body() parameters = decode_args(req_get_body_data()) end

  local app_key = parameters['appKey'] or parameters['customerNo']
  for name, value in pairs(conf.validator) do
    for validator, rule in pairs(value) do
      validators[validator]({ app = app_key, name = name, value = parameters[name] }, rule)
    end
  end
end

RequestValidatorHandler.PRIORITY = 801
return RequestValidatorHandler
