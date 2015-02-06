-- Copyright (C) Mashape, Inc.

local BaseController = require "apenode.web.routes.base_controller"

local Accounts = BaseController:extend()

function Accounts:new()
  Accounts.super.new(self, dao.accounts, "accounts") -- call the base class constructor
end

return Accounts