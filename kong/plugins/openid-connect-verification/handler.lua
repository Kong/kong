local cjson         = require "cjson.safe"
local upload        = require "resty.upload"
local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local validate      = require "kong.openid-connect.validate"
local jwt           = require "kong.openid-connect.jwt"
local set           = require "kong.openid-connect.set"
local oic           = require "kong.openid-connect"


local get_body_data = ngx.req.get_body_data
local get_post_args = ngx.req.get_post_args
local get_uri_args  = ngx.req.get_uri_args
local read_body     = ngx.req.read_body
local concat        = table.concat
local ipairs        = ipairs
local lower         = string.lower
local find          = string.find
local time          = ngx.time
local type          = type
local sub           = string.sub
local var           = ngx.var
local log           = ngx.log


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR


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
  local typ  = conf.param_type  or { "header", "query", "form", "body" }
  local ct   = var.content_type or ""
  local tok

  for _, t in ipairs(typ) do
    if t == "header" then
      tok = var["http_" .. name]

    elseif t == "query" then
      tok = get_uri_args()[name]

    elseif t == "form" then
      if sub(ct, 1, 19) == "multipart/form-data" then
        tok = multipart(name, conf.timeout)

      else
        read_body()
        tok = get_post_args()[name]
      end

    elseif t == "body" then
      read_body()
      tok = get_body_data()

      if tok and sub(ct, 1, 16) == "application/json" then
        tok = cjson.decode(tok)
        if tok then
          tok = tok[name]
        end
      end
    end

    if tok then
      break
    end
  end

  if not tok then
    log(NOTICE, "id token was not specified")
    return responses.send_HTTP_UNAUTHORIZED()
  end

  if not self.oic then
    log(NOTICE, "loading openid connect configuration")

    local o, err = oic.new {
      issuer       = conf.issuer,
      leeway       = conf.leeway                     or 0,
      http_version = conf.http_version               or 1.1,
      ssl_verify   = conf.ssl_verify == nil and true or conf.ssl_verify,
      timeout      = conf.timeout                    or 10000,
    }

    if not o then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    self.oic = o
  end

  local issuer = self.oic.configuration

  local idt, err = self.oic.jwt:decode(tok)
  if not idt then
    log(NOTICE, err)
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local idt_header  = idt.header  or {}
  local idt_payload = idt.payload or {}
  local now         = time()
  local lwy         = conf.leeway or 0
  local claims      = conf.claims or { "iss", "sub", "aud", "exp", "iat" }

  for _, c in ipairs(claims) do
    if c == "alg" then
      if not idt_header.alg then
        log(NOTICE, "alg claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local algs = issuer.id_token_signing_alg_values_supported
      if not set.has(idt_header.alg, algs) then
        log(NOTICE, "invalid alg claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "iss" then
      if idt_payload.iss ~= issuer.issuer then
        log(NOTICE, "issuer mismatch")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "sub" then
      if not idt_payload.sub then
        log(NOTICE, "sub claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "aud" then
      local aud = idt_payload.aud
      if not aud then
        log(NOTICE, "aud claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local audiences = conf.audiences

      if audiences then
        local present   = false

        if type(aud) == "string" then
          for _, audience in ipairs(audiences) do
            if audience == aud then
              present = true
              break
            end
          end

        elseif type(aud) == "table" then
          for _, audience in ipairs(audiences) do
            if set.has(audience, aud) then
              present  = true
              break
            end
          end
        end

        if not present then
          log(NOTICE, "invalid aud claim was specified for id token")
          return responses.send_HTTP_UNAUTHORIZED()
        end
      end

    elseif c == "azp" then
      local azp = idt_payload.azp
      if not azp then
        log(NOTICE, "azp claim was not specified for access token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local audiences = conf.audiences

      if audiences then
        local multiple  = type(idt_payload.aud) == "table"
        local present   = false

        if azp then
          for _, audience in ipairs(audiences) do
            if azp == audience then
              present = true
              break
            end
          end

          if not present then
            log(NOTICE, "invalid azp claim was specified for access token")
            return responses.send_HTTP_UNAUTHORIZED()
          end

        elseif multiple then
          log(NOTICE, "azp claim was not specified for access token")
          return responses.send_HTTP_UNAUTHORIZED()
        end
      end

    elseif c == "exp" then
      local exp = idt_payload.exp
      if not exp then
        log(NOTICE, "exp claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      if now - lwy > exp then
        log(NOTICE, "invalid exp claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "iat" then
      local iat = idt_payload.iat
      if not iat then
        log(NOTICE, "iat claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      if now + lwy < iat then
        log(NOTICE, "invalid iat claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "nbf" then
      local nbf = idt_payload.nbf
      if not nbf then
        log(NOTICE, "nbf claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      if now + lwy < nbf then
        log(NOTICE, "invalid nbf claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

    elseif c == "auth_time" then
      local auth_time = idt_payload.auth_time
      if not auth_time then
        log(NOTICE, "auth_time claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      if now + lwy < auth_time then
        log(NOTICE, "invalid auth_time claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local max_age = conf.max_age
      if max_age then
        local age = now - auth_time
        if age - lwy > max_age then
          log(NOTICE, "invalid auth_time claim was specified for id token")
          return responses.send_HTTP_UNAUTHORIZED()
        end
      end

    elseif c == "hd" then
      local hd = idt_payload.hd
      if not hd then
        log(NOTICE, "hd claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local present = false
      local domains = conf.domains
      if domains then
        for _, d in ipairs(domains) do
          if d == hd then
            present = true
            break
          end
        end

        if not present then
          log(NOTICE, "invalid hd claim was specified for id token")
          return responses.send_HTTP_UNAUTHORIZED()
        end
      end

    elseif c == "at_hash" then
      local at_hash = idt_payload.at_hash
      if not at_hash then
        log(NOTICE, "at_hash claim was not specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local authz = var.http_authorization
      if not authz then
        log(NOTICE, "at_hash claim cloud not be validated ")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local act_type = lower(sub(authz, 1, 6))
      if act_type ~= "bearer" then
        log(NOTICE, "at_hash claim cloud not be validated")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local act = sub(authz, 8)

      if not validate.access_token(act, at_hash, idt_header.alg) then
        log(NOTICE, "invalid at_hash claim was specified for id token")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local jwt_type = jwt.type(act)
      if jwt_type == "JWS" or jwt_type == "JWE" then
        act, err = self.oic.jwt:decode(act)
        if not act then
          log(NOTICE, err)
          return responses.send_HTTP_UNAUTHORIZED()
        end

        local act_header  = act.header  or {}
        local act_payload = act.payload or {}

        for _, claim in ipairs(conf.claims) do
          if claim == "alg" then
            if not act_header.alg then
              log(NOTICE, "alg claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            local algs = issuer.id_token_signing_alg_values_supported
            if not set.has(act_header.alg, algs) then
              log(NOTICE, "invalid alg claim was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end
          elseif claim == "iss" then
            if act_payload.iss ~= issuer.issuer then
              log(NOTICE, "invalid issuer was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

          elseif claim == "sub" then
            if not act_payload.sub then
              log(NOTICE, "sub claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

          elseif claim == "aud" then
            local aud = act_payload.aud
            if not aud then
              log(NOTICE, "aud claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            local present   = false
            local audiences = conf.audiences

            if type(aud) == "string" then
              for _, audience in ipairs(audiences) do
                if audience == aud then
                  present = true
                  break
                end
              end

            elseif type(aud) == "table" then
              for _, audience in ipairs(audiences) do
                if set.has(audience, aud) then
                  present  = true
                  break
                end
              end
            end

            if not present then
              log(NOTICE, "invalid aud claim was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

          elseif claim == "azp" then
            local azp = act_payload.azp
            if not azp then
              log(NOTICE, "azp claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            local audiences = conf.audiences

            if audiences then
              local multiple  = type(act_payload.aud) == "table"
              local present   = false

              if azp then
                for _, audience in ipairs(audiences) do
                  if azp == audience then
                    present = true
                    break
                  end
                end

                if not present then
                  log(NOTICE, "invalid azp claim was specified for access token")
                  return responses.send_HTTP_UNAUTHORIZED()
                end

              elseif multiple then
                log(NOTICE, "azp claim was not specified for access token")
                return responses.send_HTTP_UNAUTHORIZED()
              end
            end

          elseif claim == "exp" then
            local exp = act_payload.exp
            if not exp then
              log(NOTICE, "exp claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            if now - lwy > exp then
              log(NOTICE, "invalid exp claim was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

          elseif claim == "iat" then
            local iat = act_payload.iat
            if not iat then
              log(NOTICE, "iat claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            if now + lwy < iat then
              log(NOTICE, "invalid iat claim was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

          elseif claim == "nbf" then
            local nbf = act_payload.nbf
            if not nbf then
              log(NOTICE, "nbf claim was not specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end

            if now + lwy < nbf then
              log(NOTICE, "invalid nbf claim was specified for access token")
              return responses.send_HTTP_UNAUTHORIZED()
            end
          end
        end
      end
    end
  end
end


OICVerificationHandler.PRIORITY = 1000


return OICVerificationHandler
