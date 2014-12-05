-- Copyright (C) Mashape, Inc.

local Applications = require "apenode.dao.json.applications"
local Apis = require "apenode.dao.json.apis"
local Metrics = require "apenode.dao.json.metrics"

local _M = {
  apis = Apis(),
  applications = Applications(),
  metrics = Metrics()
}

return _M
