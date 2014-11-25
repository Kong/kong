-- app.lua
local lapis = require("lapis")
local app = lapis.Application()

app:get("/", function()
	return "Welcome to Lapis " .. require("lapis.version")
end)

return app