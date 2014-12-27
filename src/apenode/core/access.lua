-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"
local ApiModel = require "apenode.models.api"

local _M = {}

function _M.execute(conf)
  -- Setting the version header
  ngx.header["X-Apenode-Version"] = configuration.version

  -- Retrieving the API from the Host that has been requested
  local api, err = ApiModel.find_one({
    public_dns = stringy.split(ngx.var.http_host, ":")[1]
  })
  if not api then
    utils.not_found("API not found")
  end

  -- Setting the backend URL for the proxy_pass directive
  local querystring = ngx.encode_args(ngx.req.get_uri_args());
  ngx.var.backend_url = api.target_url .. ngx.var.uri
  ngx.var.querystring = querystring

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
