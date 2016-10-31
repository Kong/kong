local oxd = require "kong.plugins.kong-uma-rs.oxdclient"
local responses = require "kong.tools.responses"
local stringy = require "stringy"

local function isempty(s)
  return s == nil or s == ''
end

local function removeBearer(authorization)
  if authorization ~= nil and not isempty(authorization) and stringy.startswith(authorization, "Bearer ") then
    return string.sub(authorization, 8)
  end
  return ""
end

local function getRpt()
  local authorization = ngx.req.get_headers()["Authorization"]
  if type(authorization) == "string" then
    return removeBearer(authorization)
  end
  if type(authorization) == "table" then
    return removeBearer(authorization[1])
  end
  return ""
end

local function getPath()
  local path = ngx.var.request_uri
  local indexOf = string.find(path, "?")
  if indexOf ~= nil then
    return string.sub(path, 1, (indexOf - 1))
  end
  return path
end

local _M = {}

function _M.execute(conf)

  local httpMethod = ngx.req.get_method()
  local rpt = getRpt()
  local path = getPath()

  ngx.log(ngx.DEBUG, "kong-uma-rs : Access - http_method: " .. httpMethod .. ", rpt: " .. rpt .. ", path: " .. path)

  local response = oxd.checkaccess(conf, rpt, path, httpMethod)

  if response == nil then
    return responses.send_HTTP_FORBIDDEN("UMA Authorization Server Unreachable")
  end

  if response["status"] == "error" then
    ngx.log(ngx.DEBUG, "kong-uma-rs : Path is not protected! - http_method: " .. httpMethod .. ", rpt: " .. rpt .. ", path: " .. path)
    ngx.header["UMA-Warning"] = "Path is not protected by UMA. Please check protection_document."
    return
  end

  if response["status"] == "ok" then
    if response["data"]["access"] == "granted" then
      return -- ACCESS GRANTED
    end

    if response["data"]["access"] == "denied" then
      local ticket = response["data"]["ticket"]
      if not isempty(ticket) and not isempty(response["data"]["www-authenticate_header"]) then
        ngx.header["WWW-Authenticate"] = response["data"]["www-authenticate_header"]
        return responses.send_HTTP_UNAUTHORIZED("Unauthorized")
      end

      return responses.send_HTTP_FORBIDDEN("UMA Authorization Server Unreachable")
    end
  end

  return responses.send_HTTP_FORBIDDEN("Unknown (unsupported) status code from oxd server for uma_rs_check_access operation.")
end

return _M

