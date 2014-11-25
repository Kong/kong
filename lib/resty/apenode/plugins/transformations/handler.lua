-- Copyright (C) Mashape, Inc.

local header_filter = require "resty.apenode.plugins.transformations.header_filter"
local body_filter = require "resty.apenode.plugins.transformations.body_filter"

local _M = { _VERSION = '0.1' }


function _M.init()
	-- Do nothing
end


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
	header_filter.execute()
end


function _M.body_filter()
	body_filter.execute()
end


function _M.log()
	-- Do nothing
end


return _M
