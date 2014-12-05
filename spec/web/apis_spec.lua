local http = require "socket.http"

describe("/apis/ #web", function()
	pending("Later.")

	it("should pass", function()
		local result, respcode, respheaders, respstatus = http.request {
			method = "GET",
			url = "http://httpbin.org/get"
		}
		assert.True(respcode == 200)
	end)
end)