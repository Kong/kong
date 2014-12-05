-- Copyright (C) Mashape, Inc.
-- Copyright (C) Mashape, Inc.

local header_filter = require "apenode.plugins.transformations.header_filter"
local body_filter = require "apenode.plugins.transformations.body_filter"

local _M = {}

function _M.access()
  -- Do nothing
end

function _M.header_filter()
  header_filter.execute()
end

function _M.body_filter()
  body_filter.execute()
end

function _M.log()
  -- Do nothing
end

return _M
