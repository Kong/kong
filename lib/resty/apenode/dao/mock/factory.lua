-- Copyright (C) Mashape, Inc.


local application_dao = require "resty.apenode.dao.mock.application"
local api_dao = require "resty.apenode.dao.mock.api"


local _M = { 

	_VERSION = '0.1',
	api = api_dao,
	application = application_dao 

}


return _M