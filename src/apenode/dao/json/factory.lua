-- Copyright (C) Mashape, Inc.

local Applications = require "apenode.dao.json.applications"
local Apis = require "apenode.dao.json.apis"

local _M = {
  apis = Apis(),
  applications = Applications()
}

return _M
