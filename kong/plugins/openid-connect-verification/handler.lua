local upload        = require "resty.upload"
local BasePlugin    = require "kong.plugins.base_plugin"
local responses     = require "kong.tools.responses"
local oic           = require "kong.openid-connect"


local get_body_data = ngx.req.get_body_data
local get_post_args = ngx.req.get_post_args
local get_uri_args  = ngx.req.get_uri_args
local read_body     = ngx.req.read_body
local concat        = table.concat
local ipairs        = ipairs
local find          = string.find
local type          = type
local sub           = string.sub
local var           = ngx.var


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
        if d then
          if not d.filename and d.name == name then
            p = { n = 1 }
          end
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

  local n = conf.param_name
  local v

  local ct = var.content_type

  for _, t in ipairs(conf.param_type) do
    if t == "header" then
      v = var["http_" .. n]

    elseif t == "query" then
      v = get_uri_args()[n]

    elseif t == "form" then
      if sub(ct, 1, 19) == "multipart/form-data" then
        v = multipart(n, conf.timeout)

      else
        read_body()
        v = get_post_args()[n]
      end

    elseif t == "body" then
      read_body()
      v = get_body_data()
    end

    if v then
      break
    end
  end

  if not v then
    return responses.send_HTTP_BAD_REQUEST("required parameter is missing")
  end

  if not self.oic then
    local o, err = oic.new {
      issuer       = conf.issuer,
      leeway       = conf.leeway,
      http_version = conf.http_version,
      ssl_verify   = conf.ssl_verify,
      timeout      = conf.timeout,
      keepalive    = conf.keepalive,
    }

    if not o then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    self.oic = o
  end

  if self.oic:validate(v) then

  end

end

OICVerificationHandler.PRIORITY = 1000

return OICVerificationHandler
