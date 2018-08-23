local _M = {}


_M.CONSUMERS = {
  STATUS = {
    APPROVED = 0,
    PENDING  = 1,
    REJECTED = 2,
    REVOKED  = 3,
    INVITED  = 4,
  },
  TYPE = {
    PROXY     = 0,
    DEVELOPER = 1,
    ADMIN     = 2,
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
