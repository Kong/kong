-- Copyright (C) Mashape, Inc.

local access = require "apenode.plugins.authentication.access"

local _M = {}

function _M.access()
  access.execute()
end

function _M.header_filter()
  -- Do nothing
end

function _M.body_filter()
  -- Do nothing
end

function _M.log()
  -- Do nothing
end

return _M
