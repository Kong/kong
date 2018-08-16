local endpoints   = require "kong.api.endpoints"
local utils       = require "kong.tools.utils"
local responses   = require "kong.tools.responses"
local Set         = require "pl.Set"


local function get_cert_id_from_sni(self, db, helpers)
  local id = ngx.unescape_uri(self.params.certificates)
  if utils.is_valid_uuid(id) then
    return
  end

  local sni, _, err_t = db.snis:select_by_name(id)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if sni then
    self.params.certificates = sni.certificate.id
    return
  end

  if self.req.cmd_mth == "PUT" then
    self.new_put_sni = id
    return
  end

  responses.send_HTTP_NOT_FOUND("SNI not found")
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

    -- override to create a new SNI in the PUT /certificates/foo.com (create) case
    PUT = function(self, db, helpers)
      local args = self.args.post
      local cert, err_t, _
      local id = ngx.unescape_uri(self.params.certificates)

      -- cert was found via id or sni inside `before` section
      if utils.is_valid_uuid(id) then
        cert, _, err_t = db.certificates:upsert({ id = id }, args, { nulls = true })

      else -- create a new cert. Add extra sni if provided on url
        if self.new_put_sni then
          args.snis = Set.values(Set(args.snis or {}) + self.new_put_sni)
          self.new_put_sni = nil
        end
        cert, _, err_t = db.certificates:insert(args, { nulls = true })
      end

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not cert then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_OK(cert)
    end,
  },

  ["/certificates/:certificates/snis"] = {
    before = get_cert_id_from_sni,
  },
}

