local BasePlugin = require "kong.plugins.base_plugin"

local ipairs = ipairs

local initializeCtx = require 'kong.plugins.yop.interceptor.initialize_ctx'
local httpMethod = require 'kong.plugins.yop.interceptor.http_method'
local whitelist = require 'kong.plugins.yop.interceptor.whitelist'
local auth = require 'kong.plugins.yop.interceptor.auth'
local validate_sign = require 'kong.plugins.yop.interceptor.validate_sign'
local decrypt = require 'kong.plugins.yop.interceptor.decrypt'
local defaultValue = require 'kong.plugins.yop.interceptor.default_value'
local requestValidator = require 'kong.plugins.yop.interceptor.request_validator'
local requestTransformer = require 'kong.plugins.yop.interceptor.request_transformer'
local prepare_upstream = require 'kong.plugins.yop.interceptor.prepare_upstream'

local interceptors = {
  initializeCtx, httpMethod, whitelist, auth ,decrypt, validate_sign,
  defaultValue, requestValidator, requestTransformer, prepare_upstream
}

local YopHandler = BasePlugin:extend()

function YopHandler:new()
  YopHandler.super.new(self, "yop")
end

function YopHandler:access()
  YopHandler.super.access(self)
  local ctx = {}
  for _, interceptor in ipairs(interceptors) do
    interceptor.process(ctx)
  end
end

YopHandler.PRIORITY = 800
return YopHandler
