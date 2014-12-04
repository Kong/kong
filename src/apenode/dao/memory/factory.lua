-- Copyright (C) Mashape, Inc.

local Applications = require "apenode.dao.memory.applications"
local Apis = require "apenode.dao.memory.apis"

local _M = {
  apis = Apis:new(),
  applications = Applications:new()
}

return _M
