local endpoints   = require "kong.api.endpoints"
local utils       = require "kong.tools.utils"

local function get_cert_by_server_name_or_id(self, db, helpers)
  local id = self.params.certificates

  if not utils.is_valid_uuid(id) then
    local cert, _, err_t = db.certificates:select_by_server_name(id)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    self.params.certificates = cert.id
  end
end


return {
  ["/certificates"] = {
    -- override to include the server_names list when getting all certificates
    GET = function(self, db, helpers)
      local data, _, err_t, offset =
        db.certificates:page_with_name_list(self.args.size,
                                            self.args.offset)
      if not data then
        return endpoints.handle_error(err_t)
      end

      local next_page = offset and string.format("/certificates?offset=%s",
                                                 ngx.escape_uri(offset)) or ngx.null

      return helpers.responses.send_HTTP_OK {
        data   = data,
        offset = offset,
        next   = next_page,
      }
    end,

    -- override to accept the server_names param when creating a certificate
    POST = function(self, db, helpers)
      local data, _, err_t = db.certificates:insert_with_name_list(self.args.post)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_CREATED(data)
    end,
  },

  ["/certificates/:certificates"] = {
    before = get_cert_by_server_name_or_id,

    -- override to include the server_names list when getting an individual certificate
    GET = function(self, db, helpers)
      local pk = { id = self.params.certificates }

      local cert, _, err_t = db.certificates:select_with_name_list(pk)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(cert)
    end,

    -- override to accept the server_names param when updating a certificate
    PATCH = function(self, db, helpers)
      local pk = { id = self.params.certificates }
      local cert, _, err_t = db.certificates:update_with_name_list(pk, self.args.post)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      return helpers.responses.send_HTTP_OK(cert)
    end,
  },

  ["/certificates/:certificates/server_names"] = {
    before = get_cert_by_server_name_or_id,
  },
}

