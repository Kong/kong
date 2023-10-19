local certificates = require "kong.runloop.certificate"
local fmt = string.format
local kong = kong

return {
  ["/ca_certificates/:ca_certificates"] = {
    DELETE = function(self, db, helpers, parent)
      local ca_id = self.params.ca_certificates
      local entity, element_or_err = certificates.check_ca_references(ca_id)

      if entity then
        local msg = fmt("ca_certificate %s is still referenced by %s (id = %s)", ca_id, entity, element_or_err.id)
        kong.log.notice(msg)
        return kong.response.exit(400, { message = msg })
      elseif element_or_err then
        local msg = "failed to check_ca_references, " .. element_or_err
        kong.log.err(msg)
        return kong.response.exit(500, { message = msg })
      end

      return parent()
    end,
  },
}
