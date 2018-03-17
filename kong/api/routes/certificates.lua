local endpoints   = require "kong.api.endpoints"
local utils       = require "kong.tools.utils"
local responses   = require "kong.tools.responses"


local function get_cert_id_from_sni(self, db, helpers)
  local id = self.params.certificates
  if not utils.is_valid_uuid(id) then
    local sni, _, err_t = db.snis:select_by_name(id)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    if not sni then
      responses.send_HTTP_NOT_FOUND("SNI not found")
    end

    self.params.certificates = sni.certificate.id
  end
end


return {
  ["/certificates/:certificates"] = {
    before = get_cert_id_from_sni,

    -- override to include the snis list when getting an individual certificate
    GET = function(self, db, helpers)
      local pk = { id = self.params.certificates }

      local cert, _, err_t = db.certificates:select_with_name_list(pk)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(cert)
    end,
  },

  ["/certificates/:certificates/snis"] = {
    before = get_cert_id_from_sni,
  },
}

