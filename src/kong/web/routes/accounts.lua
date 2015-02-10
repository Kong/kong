-- Copyright (C) Mashape, Inc.

local BaseController = require "kong.web.routes.base_controller"

local Accounts = BaseController:extend()

function Accounts:new()
  Accounts.super.new(self, dao.accounts, "accounts")
end

return Accounts
