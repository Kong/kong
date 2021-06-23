local _M = {}


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local tostring = tostring
local assert = assert
local concat = table.concat
local sort = table.sort
local type = type


local MT = { __index = _M, }

local function table_to_sorted_string(t)
  if t == ngx_null then
    return "/null/"
  end

  local typ = type(t)
  if typ == "table" then
    local i = 1
    local o = { "{" }
    for k, v in pl_tablex.sort(t) do
      o[i+1] = table_to_sorted_string(k)
      o[i+2] = ":"
      o[i+3] = table_to_sorted_string(v)
      o[i+4] = ";"
      i=i+4
    end
    if i == 1 then
      i = i + 1
    end
    o[i] = "}"

    return concat(o, nil, 1, i)

  elseif typ == "string" then
    return '$' .. t .. '$'

  elseif typ == "number" then
    return '#' .. tostring(t) .. '#'

  elseif typ == "boolean" then
    return '?' .. tostring(t) .. '?'

  else
    return '(' .. tostring(t) .. ')'
  end
end


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, MT)

  -- note: pl_file.read throws error on failure so
  -- no need for error checking
  local cert = pl_file.read(conf.cluster_cert)
  self.cert = assert(ssl.parse_pem_cert(cert))

  cert = openssl_x509.new(cert, "PEM")
  self.cert_digest = cert:digest("sha256")

  local key = pl_file.read(conf.cluster_cert_key)
  self.cert_key = assert(ssl.parse_pem_priv_key(key))

  self.child = require("kong.clustering." .. conf.role).new(self)

  return self
end


function _M:calculate_config_hash(config_table)
  return ngx_md5(table_to_sorted_string(config_table))
end


function _M:handle_cp_websocket()
  return self.child:handle_cp_websocket()
end


function _M:init_worker()
  self.plugins_list = assert(kong.db.plugins:get_handlers())
  sort(self.plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  self.plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, self.plugins_list)

  self.child:init_worker()
end


return _M
