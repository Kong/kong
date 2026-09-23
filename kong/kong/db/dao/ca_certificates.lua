local certificate  = require "kong.runloop.certificate"
local fmt = string.format

local Ca_certificates = {}

-- returns the first encountered entity element that is referencing the ca cert
-- otherwise, returns nil, err
function Ca_certificates:check_ca_reference(ca_id)
  for _, entity in ipairs(certificate.get_ca_certificate_reference_entities()) do
    local elements, err = self.db[entity]:select_by_ca_certificate(ca_id, 1)
    if err then
      local msg = fmt("failed to select %s by ca certificate %s: %s", entity, ca_id, err)
      return nil, msg
    end

    if type(elements) == "table" and #elements > 0 then
      return entity, elements[1]
    end
  end

  local reference_plugins = certificate.get_ca_certificate_reference_plugins()
  if reference_plugins and next(reference_plugins) then
    local plugins, err = self.db.plugins:select_by_ca_certificate(ca_id, 1, reference_plugins)
    if err then
      local msg = fmt("failed to select plugins by ca_certificate %s: %s", ca_id, err)
      return nil, msg
    end

    if type(plugins) == "table" and #plugins > 0 then
      return "plugins", plugins[1]
    end
  end

  return nil, nil
end

-- Overrides the default delete function to check the ca reference before deleting
function Ca_certificates:delete(cert_pk, options)
  local entity, element_or_err = self:check_ca_reference(cert_pk.id)
  if entity then
    local msg = fmt("ca certificate %s is still referenced by %s (id = %s)",
                     cert_pk.id, entity, element_or_err.id)
    local err_t = self.errors:referenced_by_others(msg)
    return nil, tostring(err_t), err_t

  elseif element_or_err then
    local err_t = self.errors:database_error(element_or_err)
    return nil, tostring(err_t), err_t
  end

  return self.super.delete(self, cert_pk, options)
end


return Ca_certificates
