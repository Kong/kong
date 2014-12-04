-- Copyright (C) Mashape, Inc.

local BaseDao = require "apenode.dao.memory.base_dao"

local Apis = BaseDao:new()

function Apis:get_by_host(host)
  if not host then return nil end

  for k,v in pairs(self._data) do
    if v.publicn_dns == host then
      return v
    end
  end
end

return Apis