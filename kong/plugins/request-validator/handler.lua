local BasePlugin = require "kong.plugins.base_plugin"
local req_get_uri_args = ngx.req.get_uri_args
local req_get_method = ngx.req.get_method
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local ngx_decode_args = ngx.decode_args
local responses = require "kong.tools.responses"
local response, _ = require "kong.yop.response"()

local function decode_args(body) if body then return ngx_decode_args(body) end return {} end

local function send_validate_error(appKey, code, a, b)
  responses.send(200, response:new():fail():requestValidatorError(appKey):appendSubError(code, a, b))
end


local function validateNull(p) if p.value == nil then send_validate_error(p.app, "99100001", p.name) end end

local function validateBlank(p) if p.value == nil or (not not tostring(p.value):find("^%s*$")) then send_validate_error(p.app, "99100002", p.name) end end

local function validateEmail(p)
  if p.value ~= nil and not p.value:match("^[A-Za-z0-9%.]+@[%a%d]+%.[%a%d]+$") then send_validate_error(p.app, "99100008", p.name) end end

local function validateMobile(p) if p.value ~= nil and not p.value:match("^1[3|4|5|8|7]%d%d%d%d%d%d%d%d%d$") then send_validate_error(p.app, "99100009", p.name) end end

local function validateLength(p, rule)
  if p.value == nil then return end
  if rule.min ~= nil and #p.value < rule.min then send_validate_error(p.app, "99100005", p.name, rule.min) end
  if rule.max ~= nil and #p.value > rule.max then send_validate_error(p.app, "99100004", p.name, rule.max) end
end

local function validateRange(p, rule)
  if p.value == nil then return end
  local pn = tonumber(p.value)
  if pn == nil then return false end
  if rule.min ~= nil and pn < rule.min then send_validate_error(p.app, "99100007", p.name, rule.min) end
  if rule.max ~= nil and pn > rule.max then send_validate_error(p.app, "99100006", p.name, rule.max) end
end

local function validateInt(p)
  if p.value ~= nil and not p.value:match("^[-+]?[%d]*$") then send_validate_error(p.app, "99100011", p.name) end
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
