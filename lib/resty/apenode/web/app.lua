-- Copyright (C) Mashape, Inc.


local lapis = require("lapis")
local app_helpers = require("lapis.application")
local validate = require("lapis.validate")
local utils = require "resty.apenode.utils"


local app = lapis.Application()


app:get("/", function()
	return utils.show_response(200, "Welcome to Apenode")
end)


return app