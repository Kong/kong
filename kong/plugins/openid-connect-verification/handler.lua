local cjson         = require "cjson.safe"
local upload        = require "resty.upload"
local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local cache         = require "kong.plugins.openid-connect.cache"
local codec         = require "kong.openid-connect.codec"
local set           = require "kong.openid-connect.set"
local uri           = require "kong.openid-connect.uri"
local oic           = require "kong.openid-connect"


local get_body_data = ngx.req.get_body_data
local get_body_file = ngx.req.get_body_file
local get_post_args = ngx.req.get_post_args
local get_uri_args  = ngx.req.get_uri_args
local base64url     = codec.base64url
local set_header    = ngx.req.set_header
local read_body     = ngx.req.read_body
local header        = ngx.header
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


local function unauthorized(iss, err)
  if err then
    log(NOTICE, err)
  end
  local parts = uri.parse(iss)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
end


local function internalerror(err)
  if err then
    log(ERR, err)
  end
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


local OICVerificationHandler = BasePlugin:extend()


function OICVerificationHandler:new()
  OICVerificationHandler.super.new(self, "openid-connect-verification")
end


function OICVerificationHandler:access(conf)
  OICVerificationHandler.super.access(self)

  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    return internalerror(err)
  end

  local o

  o, err = oic.new({
    clients      = conf.clients,
    audience     = conf.audience,
    claims       = conf.claims       or { "iss", "sub", "aud", "azp", "exp" },
    domains      = conf.domains,
    max_age      = conf.max_age,
    timeout      = conf.timeout      or 10000,
    leeway       = conf.leeway       or 0,
    http_version = conf.http_version or 1.1,
    ssl_verify   = conf.ssl_verify == nil and true or conf.ssl_verify,

  }, issuer.configuration, issuer.keys)

  if not o then
    return internalerror(err)
  end

  local iss    = o.configuration.issuer
  local tokens = conf.tokens or { "id_token" }

  local idt

  if set.has("id_token", tokens) then
    local ct     = var.content_type  or ""
    local name   = conf.param_name   or "id_token"
    local typ    = conf.param_type   or { "query", "header", "body" }
    local prefix = conf.param_prefix or "x_"

    for _, t in ipairs(typ) do
      if t == "header" then
        local header = "http_" .. gsub(lower(prefix .. name), "-", "_")
        idt = var[header]
        if idt then
          break
        end

      elseif t == "query" then
        local args = get_uri_args()
        if args then
          idt = args[name]
          if idt then
            break
          end
        end

      elseif t == "body" then
        if sub(ct, 1, 33) == "application/x-www-form-urlencoded" then
          read_body()
          local args = get_post_args()
          if args then
            idt = args[name]
            if idt then
              break
            end
          end

        elseif sub(ct, 1, 19) == "multipart/form-data" then
          idt = multipart(name, conf.timeout)
          if idt then
            break
          end

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
              if idt then
                break
              end
            end
          end

        else
          read_body()
          local data = get_body_data()
          if data == nil then
            local file = get_body_file()
            if file ~= nil then
              idt = read_file(file)
              if idt then
                break
              end
            end
          end
        end
      end
    end

    if not idt then
      return unauthorized(iss, "id token was not specified")
    end
  end

  local act

  if set.has("access_token", tokens) then
    act = o.token:bearer()
    if not act then
      return unauthorized(iss, "access token was not specified")
    end
  elseif idt then
    act = o.token:bearer()
  end

  local toks = {
    id_token     = idt,
    access_token = act
  }

  local options = {
    tokens = tokens
  }

  local tks, err = o.token:verify(toks, options)

  if type(tks) ~= "table" then
    return unauthorized(iss, err)
  end

  local kids = {}
  local jwks = {}
  local keys = 0

  local jwks_header = conf.jwks_header
  if jwks_header == "" then
    jwks_header = nil
  end

  for _, t in ipairs(tokens) do
    if type(tks[t]) ~= "table" then
      return unauthorized(iss, gsub(lower(t), "_", " ") .. " was not verified")
    elseif jwks_header then
      local jwk = tks[t].jwk

      if type(jwk) ~= "table" then
        return unauthorized(iss, "invalid jwk was specified for " .. gsub(lower(t), "_", " "))
      end

      if jwk then
        if not kids[jwk.kid] then
          keys = keys + 1
          kids[jwk.kid] = true
          jwks[keys] = jwk
        end
      end
    end
  end

  local sco = conf.session_cookie
  if sco and sco ~= "" then
    local value = var["cookie_" .. sco]
    if not value or value == "" then
      return unauthorized(iss, "session cookie was not specified for session claim verification")
    end

    local act = tks.access_token
    if not act then
      return unauthorized(iss, "access token was not specified for session claim verification")
    end
    if type(act) ~= "table" then
      return unauthorized(iss, "opaque access token was specified for session claim verification")
    end

    local claim = act.payload[conf.session_claim or "sid"]

    if not claim then
      return unauthorized(iss, "session claim (" .. claim .. ") was not specified in access token")
    end

    if claim ~= value then
      return unauthorized(iss, "invalid session claim (" .. claim .. ") was specified in access token")
    end
  end

  if keys > 0 then
    jwks, err = cjson.encode(jwks)
    if not jwks then
      return internalerror(err)
    end
    jwks, err = base64url.encode(jwks)
    if not jwks then
      return internalerror(err)
    end

    set_header(jwks_header, jwks)
  end
end


OICVerificationHandler.PRIORITY = 900


return OICVerificationHandler
