local ffi = require("ffi")
local base = require("resty.core.base")
local sha256 = require("kong.tools.utils").sha256_bin
local get_dbi = require("resty.lmdb.transaction").get_dbi


local kong = kong
local C = ffi.C
local ffi_new = ffi.new
local ffi_string = ffi.string
local ffi_typeof = ffi.typeof


local MAX_KEY_SIZE = 511 -- lmdb has 511 bytes limitation for key
local DEFAULT_DB = "_default"
local ERROR = ngx.ERROR


local OPS_T = ffi_typeof("ngx_lua_resty_lmdb_operation_t[?]")
local ERR_P = base.get_errmsg_ptr()


local function set(self, key, value)
  if value == nil or key == nil then
    return
  end

  if #key > MAX_KEY_SIZE then
    key = sha256(key)
  end

  local n = self.n + 1
  self.n = n
  self.k[n] = key
  self.v[n] = value
end


local function del(self, key)
  if key == nil then
    return
  end

  if #key > MAX_KEY_SIZE then
    key = sha256(key)
  end

  local n = self.n + 1
  self.n = n
  self.k[n] = key
end


local function commit(self, db)
  local n = self.n

  if n == 0 then
    return
  end

  local dbi, err = get_dbi(true, db or DEFAULT_DB)
  if err then
    return nil, "unable to open DB for access: " .. err
  elseif not dbi then
    return nil, "DB " .. db .. " does not exist"
  end

  local ops = ffi_new(OPS_T, n)
  for i = 0, n - 1 do
    local k = self.k[i + 1]
    local v = self.v[i + 1]

    ops[i].opcode = C.NGX_LMDB_OP_SET
    ops[i].key.data = k
    ops[i].key.len = #k

    if v then
      ops[i].value.data = v
      ops[i].value.len = #v
    else
      ops[i].value.data = nil
      ops[i].value.len = 0
    end

    ops[i].dbi = dbi
    ops[i].flags = 0
  end

  local ret = C.ngx_lua_resty_lmdb_ffi_execute(ops, n, 1, nil, 0, ERR_P)
  if ret == ERROR then
    return nil, ffi_string(ERR_P[0])
  end

  return true
end


return {
  begin = function(hint)
    return {
      k = kong.table.new(hint or 10000, 0),
      v = kong.table.new(hint or 10000, 0),
      n = 0,
      commit = commit,
      set = set,
      del = del,
    }
  end
}
