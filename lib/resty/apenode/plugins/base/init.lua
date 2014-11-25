-- Copyright (C) Mashape, Inc.


local yaml = require "yaml"


local _M = { _VERSION = '0.1' }


function _M.execute()
	ngx.log(ngx.DEBUG, "Base Init Filter")

	local file = io.open("/etc/apenode/conf.yaml", "rb")
	local contents = file:read("*all")
	file:close()

	-- Loading configuration
	configuration = yaml.load(contents)
	dao = require(configuration.dao_factory)
end


return _M
