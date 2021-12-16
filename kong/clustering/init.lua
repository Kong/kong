local _M = {}


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local isempty = require("table.isempty")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local new_tab = require("table.new")
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local tostring = tostring
local assert = assert
local error = error
local concat = table.concat
local pairs = pairs
local sort = table.sort
local type = type


local MT = { __index = _M, }


local function to_sorted_string(value)
  if value == ngx_null then
    return "/null/"
  end

  local t = type(value)
  if t == "string" then
    return "$" .. value .. "$"

  elseif t == "number" then
    return "#" .. value .. "#"

  elseif t == "boolean" then
    return "?" .. tostring(value) .. "?"

  elseif t == "table" then
    if isempty(value) then
      return "{}"

    elseif isarray(value) then
      local count = #value
      local narr = count * 2 + 1
      local o = new_tab(narr, 0)
      local i = 1
      o[i] = "{"
      for j = 1, count do
        o[i+1] = to_sorted_string(value[j])
        o[i+2] = ";"
        i=i+2
      end
      o[i] = "}"
      return concat(o, nil, 1, narr)

    else
      local count = nkeys(value)
      local keys = new_tab(count, count)
      local i = 0
      for k in pairs(value) do
        i = i + 1
        local key = to_sorted_string(k)
        keys[i] = key
        keys[key] = k
      end

      sort(keys)

      local narr = count * 4 + 1
      local o = new_tab(narr, 0)
      i = 1
      o[i] = "{"
      for j = 1, count do
        local key = keys[j]
        o[i+1] = key
        o[i+2] = ":"
        o[i+3] = to_sorted_string(value[keys[key]])
        o[i+4] = ";"
        i=i+4
      end
      o[i] = "}"
      return concat(o, nil, 1, narr)
    end

  else
    error("invalid type to be sorted (JSON types are supported")
  end
end


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, MT)

  local cert = assert(pl_file.read(conf.cluster_cert))
  self.cert = assert(ssl.parse_pem_cert(cert))

  cert = openssl_x509.new(cert, "PEM")
  self.cert_digest = cert:digest("sha256")

  local key = assert(pl_file.read(conf.cluster_cert_key))
  self.cert_key = assert(ssl.parse_pem_priv_key(key))

  self.child = require("kong.clustering." .. conf.role).new(self)

  return self
end


function _M:calculate_config_hash(config_table)
  return ngx_md5(to_sorted_string(config_table))
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
