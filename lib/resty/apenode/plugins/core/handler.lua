-- Copyright (C) Mashape, Inc.

local access = require "resty.apenode.plugins.core.access"
local header_filter = require "resty.apenode.plugins.core.header_filter"
local log = require "resty.apenode.plugins.core.log"


local _M = { _VERSION = '0.1' }


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
	header_filter.execute()
end


function _M.body_filter()
	-- Do nothing
end


function _M.log()
	log.execute()
end


return _M
