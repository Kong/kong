-- Copyright (C) Mashape, Inc.


local _M = { _VERSION = '0.1' }


function _M.get_by_host(host)
	if not host then return nil end

	-- This is just a mock response
	return {
		id = "api123",
		backend_url = "https://httpbin.org",
		authentication_key_name = "apikey",
		authentication_header_name = nil,
		transformations = {
			xml_to_json = true
		}
	}
end


return _M