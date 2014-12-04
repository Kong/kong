-- Copyright (C) Mashape, Inc.

local lapis = require("lapis")
local app_helpers = require("lapis.application")
local validate = require("lapis.validate")
local utils = require "apenode.core.utils"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

local app = lapis.Application()

app:get("/", function(self)
  return utils.show_response(200, "Welcome to Apenode")
end)

require("apenode.web.apis").init(app)
require("apenode.web.applications").init(app)

return app