-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"
local ApiModel = require "apenode.models.api"

local _M = {}

local function get_backend_url(api)
  local result = api.target_url

  -- Checking if the target url ends with a final slash
  local len = string.len(result)
  if string.sub(result, len, len) == "/" then
    -- Remove one slash to avoid having a double slash
    -- Because ngx.var.uri always starts with a slash
    result = string.sub(result, 0, len - 1)
  end

  return result
end

function _M.execute(conf)
  -- Setting the version header
  ngx.header["X-Apenode-Version"] = configuration.version

  -- Retrieving the API from the Host that has been requested
  local api, err = ApiModel.find_one({
    public_dns = stringy.split(ngx.var.http_host, ":")[1]
  }, dao)
  if not api then
    utils.not_found("API not found")
  end

  -- Setting the backend URL for the proxy_pass directive
  ngx.var.backend_url = get_backend_url(api) .. ngx.var.request_uri

  -- TODO: Move this away from here
  -- There are some requests whose authentication needs to be skipped
  if skip_authentication(ngx.req.get_headers()) then
    return -- Returning and keeping the Lua code running to the next handler
  end

  -- Saving these properties for the other handlers, especially the log handler
  ngx.ctx.api = api
end

function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and _M.starts_with(headers["expect"], "100")
end

return _M
