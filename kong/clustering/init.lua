local _M = {}


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local openssl_digest = require("resty.openssl.digest")
local to_hex = require("resty.string").to_hex
local ngx_null = ngx.null
local tostring = tostring
local assert = assert
local error = error
local sort = table.sort
local type = type


local MT = { __index = _M, }


local compare_sorted_strings


local function hash_config(value, hash)
  if value == ngx_null then
    hash:update("/null/")
    return
  end

  local t = type(value)
  if t == "table" then
    hash:update("{")
    for k, v in pl_tablex.sort(value, compare_sorted_strings) do
      hash_config(k, hash)
      hash:update(":")
      hash_config(v, hash)
      hash:update(";")
    end
    hash:update("}")

  elseif t == "string" then
    hash:update("$")
    hash:update(value)
    hash:update("$")

  elseif t == "number" then
    hash:update("#")
    hash:update(tostring(value))
    hash:update("#")

  elseif t == "boolean" then
    hash:update("?")
    hash:update(tostring(value))
    hash:update("?")

  else
    error("invalid type to be sorted (JSON types are supported")
  end
end


compare_sorted_strings = function(a, b)
  local md5 = openssl_digest.new("MD5")
  a = hash_config(a, md5)
  a = to_hex((md5:final()))
  md5 = openssl_digest.new("MD5")
  b = hash_config(b, md5)
  b = to_hex((md5:final()))
  return a < b
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
  local md5, err = openssl_digest.new("MD5")
  if not md5 then
    return nil, err
  end

  hash_config(config_table, md5)

  local digest, err = md5:final()
  if not digest then
    return nil, err
  end

  return to_hex(digest)
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
