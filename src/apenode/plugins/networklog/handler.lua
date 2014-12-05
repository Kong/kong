-- Copyright (C) Mashape, Inc.

local log = require "apenode.plugins.networklog.log"

local _M = {}

function _M.access()
  -- Do nothing
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
