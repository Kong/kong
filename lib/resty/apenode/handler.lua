-- Copyright (C) Mashape, Inc.

local init = require "resty.apenode.init"
local access = require "resty.apenode.access"
local content = require "resty.apenode.content"
local rewrite = require "resty.apenode.rewrite"
local header_filter = require "resty.apenode.header_filter"
local body_filter = require "resty.apenode.body_filter"
local log = require "resty.apenode.log"

local _M = { _VERSION = '0.1' }


function _M.init()
	init.execute()
end


function _M.access()
	access.execute()
end


function _M.content()
	content.execute()
end


function _M.rewrite()
	rewrite.execute()
end


function _M.header_filter()
	header_filter.execute()
end


function _M.body_filter()
	body_filter.execute()
end


function _M.log()
	log.execute()
end


return _M
