local _M = {}


local pl_file = require("pl.file")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")


local MT = { __index = _M, }


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

  self.child = require("kong.hybrid." .. conf.role).new(self)

  return self
end


function _M:handle_cp_protocol()
  return self.child:handle_cp_protocol()
end


function _M:register_callback(topic, callback)
  return self.child:register_callback(topic, callback)
end


function _M:send(message)
  return self.child:send(message)
end


function _M:init_worker()
  self.child:init_worker()
end


return _M
