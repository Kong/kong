-- Copyright (C) Mashape, Inc.

local Accounts = require "apenode.dao.cassandra.accounts"
local Applications = require "apenode.dao.cassandra.applications"
local Apis = require "apenode.dao.cassandra.apis"
local Metrics = require "apenode.dao.cassandra.metrics"

local _M = {
  apis = Apis(),
  accounts = Accounts(),
  applications = Applications(),
  metrics = Metrics()
}

return _M
