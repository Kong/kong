local cjson         = require "cjson.safe"
local upload        = require "resty.upload"
local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local codec         = require "kong.openid-connect.codec"
local oic           = require "kong.openid-connect"


local get_body_data = ngx.req.get_body_data
local get_body_file = ngx.req.get_body_file
local get_post_args = ngx.req.get_post_args
local get_uri_args  = ngx.req.get_uri_args
local base64url     = codec.base64url
local set_header    = ngx.req.set_header
local read_body     = ngx.req.read_body
local concat        = table.concat
local ipairs        = ipairs
local lower         = string.lower
local gsub          = string.gsub
local find          = string.find
local open          = io.open
local type          = type
local sub           = string.sub
local var           = ngx.var
local log           = ngx.log


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR


local function read_file(f)
  local f, e = open(f, "rb")
  if not f then
    return nil, e
  end
  local c = f:read "*a"
  f:close()
  return c
end


local function kv(r, s)
  if s == "formdata" then return end
  local e = find(s, "=", 1, true)
  if e then
    r[sub(s, 2, e - 1)] = sub(s, e + 2, #s - 1)
  else
    r[#r+1] = s
  end
end


local function parse(s)
  if not s then return nil end
  local r = {}
  local i = 1
  local b = find(s, ";", 1, true)
  while b do
    local p = sub(s, i, b - 1)
    kv(r, p)
    i = b + 1
    b = find(s, ";", i, true)
  end
  local p = sub(s, i)
  if p ~= "" then kv(r, p) end
  return r
end


local function multipart(name, timeout)
  local form = upload:new()
  if not form then return nil end
  local h, p
  form:set_timeout(timeout)
  while true do
    local t, r = form:read()
    if not t then return nil end
    if t == "header" then
      if not h then h = {} end
      if type(r) == "table" then
        local k, v = r[1], parse(r[2])
        if v then h[k] = v end
      end
    elseif t == "body" then
      if h then
        local d = h["Content-Disposition"]
        if d and d.name == name then
          p = { n = 1 }
        end
        h = nil
      end
      if p then
        local n = p.n
        p[n] = r
        p.n  = n + 1
      end
    elseif t == "part_end" then
      local c, d
      if p then
        p = concat(p)
        break
      end
    elseif t == "eof" then
      break
    end
  end
  local t = form:read()
  if not t then return nil end
  return p
end


local OICVerificationHandler = BasePlugin:extend()


function OICVerificationHandler:new()
  OICVerificationHandler.super.new(self, "openid-connect-verification")
end


function OICVerificationHandler:access(conf)
  OICVerificationHandler.super.access(self)

  local name = conf.param_name  or "id_token"
  local typ  = conf.param_type  or { "query", "header", "body" }
  local ct   = var.content_type or ""
  local idt

  for _, t in ipairs(typ) do
    if t == "header" then
      local header = "http_" .. gsub(lower(name), "-", "_")
      idt = var[header]

    elseif t == "query" then
      local args = get_uri_args()
      if args then
        idt = args[name]
      end

    elseif t == "body" then
      if sub(ct, 1, 33) == "application/x-www-form-urlencoded" then
        read_body()
        local args = get_post_args()
        if args then
          idt = args[name]
        end

      elseif sub(ct, 1, 19) == "multipart/form-data" then
        idt = multipart(name, conf.timeout)

      elseif sub(ct, 1, 16) == "application/json" then
        read_body()
        local data = get_body_data()
        if data == nil then
          local file = get_body_file()
          if file ~= nil then
            data = read_file(file)
          end
        end
        if data then
          local json = cjson.decode(data)
          if json then
            idt = json[name]
          end
        end

      else
        read_body()
        local data = get_body_data()
        if data == nil then
          local file = get_body_file()
          if file ~= nil then
            idt = read_file(file)
          end
        end
      end
    end

    if idt then
      break
    end
  end

  if not idt then
    log(NOTICE, "id token was not specified")
    return responses.send_HTTP_UNAUTHORIZED()
  end

  if not self.oic then
    log(NOTICE, "loading openid connect configuration")

    local claims = conf.claims or { "iss", "sub", "aud", "azp", "exp", "iat" }

    local o, err = oic.new {
      issuer       = conf.issuer,
      leeway       = conf.leeway                     or 0,
      http_version = conf.http_version               or 1.1,
      ssl_verify   = conf.ssl_verify == nil and true or conf.ssl_verify,
      timeout      = conf.timeout                    or 10000,
      audiences    = conf.audiences,
      max_age      = conf.max_age,
      domains      = conf.domains,
      claims       = claims
    }

    if not o then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    self.oic = o
  end

  local act = self.oic.token:bearer()

  local tokens = {
    id_token     = idt,
    access_token = act
  }

  local tks, err = self.oic.token:verify(tokens)

  if type(tks) ~= "table" then
    log(NOTICE, err)
    return responses.send_HTTP_UNAUTHORIZED()
  end

  idt = tks.id_token
  if type(idt) ~= "table" then
    log(NOTICE, "id token was not verified")
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local jwk_header = conf.jwk_header

  if jwk_header then
    local jwk = idt.jwk
    if type(idt) ~= "table" then
      log(NOTICE, "invalid jwk was specified")
      return responses.send_HTTP_UNAUTHORIZED()
    end

    jwk, err = cjson.encode(jwk)
    if not jwk then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    jwk, err = base64url.encode(jwk)
    if not jwk then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    set_header(jwk_header, jwk)
  end
end


OICVerificationHandler.PRIORITY = 1000


return OICVerificationHandler
