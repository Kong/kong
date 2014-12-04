-- Copyright (C) Mashape, Inc.

local BaseDao = require "apenode.dao.memory.base_dao"

local Applications = BaseDao:new()

function Applications:is_valid(application, api)
  if not application or not api then return false end

  return true
end

return Applications