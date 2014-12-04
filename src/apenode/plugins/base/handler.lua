-- Copyright (C) Mashape, Inc.

local access = require "apenode.plugins.base.access"
local log = require "apenode.plugins.base.log"

local _M = {}

function _M.access()
  access.execute()
end

function _M.content()
  -- Do nothing
end

function _M.rewrite()
  -- Do nothing
end

function _M.header_filter()
  -- Do nothing
end

function _M.body_filter()
  -- Do nothing
end

function _M.log()
  log.execute()
end

return _M
