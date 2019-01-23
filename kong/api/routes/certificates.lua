local endpoints   = require "kong.api.endpoints"
local utils       = require "kong.tools.utils"
local Set         = require "pl.Set"


local kong = kong
local unescape_uri = ngx.unescape_uri


local function get_cert_id_from_sni(self, db, helpers)
  local id = unescape_uri(self.params.certificates)
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

  if self.req.method == "PUT" then
    return
  end

  return kong.response.exit(404, { message = "SNI not found" })
end


return {
  ["/certificates/:certificates"] = {
    before = get_cert_id_from_sni,

    -- override to include the snis list when getting an individual certificate
    GET = endpoints.get_entity_endpoint(kong.db.certificates.schema,
                                        nil, nil, "select_with_name_list"),

    -- override to create a new SNI in the PUT /certificates/foo.com (create) case
    PUT = function(self, db, helpers)
      local cert, err_t, _
      local id = unescape_uri(self.params.certificates)

      -- cert was found via id or sni inside `before` section
      if utils.is_valid_uuid(id) then
        cert, _, err_t = endpoints.upsert_entity(self, db, db.certificates.schema)

      else -- create a new cert. Add extra sni if provided on url
        self.args.post.snis = Set.values(Set(self.args.post.snis or {}) + id)
        cert, _, err_t = endpoints.insert_entity(self, db, db.certificates.schema)
      end

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not cert then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200, cert)
    end,
  },

  ["/certificates/:certificates/snis"] = {
    before = get_cert_id_from_sni,
  },
}

