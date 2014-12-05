-- Copyright (C) Mashape, Inc.

local access = require "apenode.core.access"
local header_filter = require "apenode.core.header_filter"

function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and _M.starts_with(headers["expect"], "100")
end

local _M = {}

function _M.access()
  access.execute()
end

function _M.header_filter()
  header_filter.execute()
end

function _M.body_filter()
  -- Do nothing
end

function _M.log()
  -- Do nothing
end

return _M
