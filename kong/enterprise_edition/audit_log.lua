local cjson = require "cjson"
local pl_file = require "pl.file"
local pl_sort = require "pl.tablex".sort
local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"


local _M = {}


local SIGNING_ALGORITHM = "SHA256"


local signing_key


local function serialize(data)
  local p = {}

  for k, v in pl_sort(data) do
    if type(v) == "table" then
      p[#p + 1] = serialize(v)
    else
      p[#p + 1] = v
    end
  end

  return p
end


local function sign_adjacent(data)
  if not signing_key then
    local resty_rsa = require "resty.rsa"


    local k = singletons.configuration.audit_log_signing_key
    local err


    signing_key, err = resty_rsa:new({
      private_key = pl_file.read(k),
      algorithm   = SIGNING_ALGORITHM,
    })
    if not signing_key then
      ngx.log(ngx.ERR, "Could not create signing key object: ", err)
      return
    end
  end


  local sig, err = signing_key:sign(table.concat(serialize(data), "|"))
  if not sig then
    ngx.log(ngx.ERR, err)
    return
  end


  data.signature = ngx.encode_base64(sig)


  return
end


local function dao_audit_handler(data)
  if data.schema.name == "audit_objects" or data.schema.name == "audit_requests" then
    return
  end

  if utils.table_contains(singletons.configuration.audit_log_ignore_tables,
                          data.schema.name) then
    return
  end


  local data = {
    request_id = ngx.ctx.admin_api.req_id,
    entity_key = data.entity[data.schema.primary_key[1]],
    dao_name   = data.schema.table or data.schema.name,
    operation  = data.operation,
    entity     = cjson.encode(data.entity),
  }

  local ttl = singletons.configuration.audit_log_record_ttl

  if type(ngx.ctx.rbac) == "table" then
    data.rbac_user_id = ngx.ctx.rbac.user.id
  end


  if singletons.configuration.audit_log_signing_key then
    sign_adjacent(data)
  end


  local ok, err = singletons.db.audit_objects:insert(data,
    { ttl = ttl }
  )
  if not ok then
    ngx.log(ngx.ERR, "failed to write audit log entry: ", err)
  end


  return
end
_M.dao_audit_handler = dao_audit_handler


local function audit_log_writer(_, data)
  local ttl = singletons.configuration.audit_log_record_ttl

  local ok, err = singletons.db.audit_requests:insert(data,
    { ttl = ttl }
  )
  if not ok then
    ngx.log(ngx.ERR, "failed to write audit log entry: ", err)
  end

  return
end


local function admin_log_handler()
  -- if we never started the lapis execution (because this is an OPTIONS
  -- request or something as such)
  if not ngx.ctx.admin_api then
    return
  end

  if not singletons.configuration.audit_log then
    return
  end

  if utils.table_contains(singletons.configuration.audit_log_ignore_methods,
                          ngx.req.get_method()) then
    return
  end

  local uri = ngx.var.request_uri
  if singletons.configuration.audit_log_ignore_paths then
    for _, p in ipairs(singletons.configuration.audit_log_ignore_paths) do
      if string.find(uri, p, nil, true) then
        return
      end
    end
  end

  local data = {
    request_id   = ngx.ctx.admin_api.req_id,
    client_ip    = ngx.var.remote_addr,
    path         = uri,
    payload      = ngx.req.get_body_data(),
    method       = ngx.req.get_method(),
    status       = ngx.status,
    workspace    = ngx.ctx.workspaces and ngx.ctx.workspaces[1] and
                   ngx.ctx.workspaces[1].id,
  }


  if type(ngx.ctx.rbac) == "table" then
    data.rbac_user_id = ngx.ctx.rbac.user.id
  end


  if singletons.configuration.audit_log_signing_key then
    sign_adjacent(data)
  end


  local ok, err = ngx.timer.at(0, audit_log_writer, data)
  if not ok then
    ngx.log(ngx.ERR, "failed creating dummy req for audit log write: ", err)
  end


  return
end
_M.admin_log_handler = admin_log_handler


return _M
