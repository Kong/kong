-- Copyright (C) Mashape, Inc.

local access = require "resty.apenode.base.access"
local header_filter = require "resty.apenode.base.header_filter"
local log = require "resty.apenode.base.log"
local utils = require "resty.apenode.utils"


local _M = { _VERSION = '0.1' }


function _M.init()
	-- Do nothing
end


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
	utils.create_timer(log.execute, ngx.ctx.log_message)
end


return _M
