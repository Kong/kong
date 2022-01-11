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
local ngx_md5_bin = ngx.md5_bin
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
  if t == "string" or t == "number" then
    return value

  elseif t == "boolean" then
    return tostring(value)

  elseif t == "table" then
    if isempty(value) then
      return "{}"

    elseif isarray(value) then
      local count = #value
      if count == 1 then
        return to_sorted_string(value[1])

      elseif count == 2 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2])

      elseif count == 3 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3])

      elseif count == 4 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4])

      elseif count == 5 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4]) .. ";" ..
               to_sorted_string(value[5])
      end

      local i = 0
      local o = new_tab(count < 100 and count or 100, 0)
      for j = 1, count do
        i = i + 1
        o[i] = to_sorted_string(value[j])

        if j % 100 == 0 then
          i = 1
          o[i] = ngx_md5_bin(concat(o, ";", 1, 100))
        end
      end

      return ngx_md5_bin(concat(o, ";", 1, i))

    else
      local count = nkeys(value)
      local keys = new_tab(count, 0)
      local i = 0
      for k in pairs(value) do
        i = i + 1
        keys[i] = k
      end

      sort(keys)

      local o = new_tab(count, 0)
      for i = 1, count do
        o[i] = keys[i] .. ":" .. to_sorted_string(value[keys[i]])
      end

      value = concat(o, ";", 1, count)

      return #value > 512 and ngx_md5_bin(value) or value
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
