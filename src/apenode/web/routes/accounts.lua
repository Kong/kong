-- Copyright (C) Mashape, Inc.

local AccountModel = require "apenode.models.account"
local BaseController = require "apenode.web.routes.base_controller"

local Accounts = BaseController:extend()

function Accounts:new()
  Accounts.super:new(AccountModel) -- call the base class constructor
end

return Accounts