-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}


_M.CONSUMERS = {
  STATUS = {
    APPROVED   = 0,
    PENDING    = 1,
    REJECTED   = 2,
    REVOKED    = 3,
    INVITED    = 4,
    UNVERIFIED = 5,
  },
  TYPE = {
    PROXY       = 0,
    DEVELOPER   = 1,
    ADMIN       = 2,
    APPLICATION = 3,
  },
  STATUS_LABELS = {},
  TYPE_LABELS   = {},
}


_M.TOKENS = {
  STATUS = {
    PENDING = 1,
    CONSUMED = 2,
    INVALIDATED = 3,
  }
}


for k, v in pairs(_M.CONSUMERS.STATUS) do
  _M.CONSUMERS.STATUS_LABELS[v] = k
end


for k, v in pairs(_M.CONSUMERS.TYPE) do
  _M.CONSUMERS.TYPE_LABELS[v] = k
end


return _M
