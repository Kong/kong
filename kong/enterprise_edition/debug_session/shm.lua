-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.enterprise_edition.debug_session.utils"

local log = utils.log
local ngx_ERR = ngx.ERR

local SHM_NAME = "kong_debug_session"

local Cfg = {}
Cfg.__index = Cfg


function Cfg:new()
  local shm = ngx.shared[SHM_NAME]
  if not shm then
    error("Shared memory dictionary '" .. SHM_NAME .. "' not found.")
  end
  local obj = {
    shm = shm,
  }
  setmetatable(obj, self)
  return obj
end

-- Method to set a value to the predefined key
function Cfg:set(key, value)
  local ok, shm_err = self.shm:set(key, value)
  if not ok then
    log(ngx_ERR, "Failed to set value in shm: ", shm_err)
    return nil, shm_err
  end
  return true
end

function Cfg:get(key)
  return self.shm:get(key)
end

function Cfg:incr()
  local count, err = self.shm:incr("counter", 1, 0)
  if not count then
    log(ngx_ERR, "Failed to increment value in shm: ", err)
    return nil, err
  end
  return count
end

function Cfg:flush()
  self.shm:flush_all()
end

return Cfg
