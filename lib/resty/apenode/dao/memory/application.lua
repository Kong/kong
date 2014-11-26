-- Copyright (C) Mashape, Inc.


local _M = { _VERSION = '0.1' }


function _M.get_by_key(key)
	if not key then return nil end
	
	-- This is just a mock response
	return {
		id = "application123",
		key = application_key,
		throttle = nil,
		account = {
			id = "account123",
			throttle = nil
		}
	}
end


function _M.is_valid(application, api)
	if not application or not api then return false end

	-- This is just a mock response
	return true
end


return _M