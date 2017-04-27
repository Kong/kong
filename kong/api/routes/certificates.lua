local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


return {
  ["/certificates/"] = {
    POST = function(self, dao_factory, helpers)
      local snis
      if type(self.params.snis) == "string" then
        snis = utils.split(self.params.snis, ",")
        self.params.snis = nil
      end

      if snis then
        -- dont add the certificate or any snis if we have an SNI conflict
        -- its fairly inefficient that we have to loop twice over the datastore
        -- but no support for OR queries means we gotsta!
        local seen = {}

        for _, sni in ipairs(snis) do
          if seen[sni] then
            return helpers.responses.send_HTTP_CONFLICT(
              "duplicate requested sni name " .. sni
            )
          end

          local cnt, err = dao_factory.ssl_servers_names:count({
            name = sni,
          })
          if err then
            return helpers.yield_error(err)
          end

          if cnt > 0 then
            return helpers.responses.send_HTTP_CONFLICT(
              "entry already exists with name " .. sni
            )
          end

          seen[sni] = true
        end
      end

      local ssl_cert, err = dao_factory.ssl_certificates:insert(self.params)
      if err then
        return helpers.yield_error(err)
      end

      -- insert SNIs if given

      if snis then
        ssl_cert.snis = {}

        for _, sni in ipairs(snis) do
          local ssl_server_name = {
            name                = sni,
            ssl_certificate_id  = ssl_cert.id,
          }

          local row, err = dao_factory.ssl_servers_names:insert(ssl_server_name)
          if err then
            return helpers.yield_error(err)
          end

          table.insert(ssl_cert.snis, row.name)
        end
      end

      return helpers.responses.send_HTTP_CREATED(ssl_cert)
    end,


    GET = function(self, dao_factory, helpers)
      local ssl_certificates, err = dao_factory.ssl_certificates:find_all()
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #ssl_certificates do
        local rows, err = dao_factory.ssl_servers_names:find_all {
          ssl_certificate_id = ssl_certificates[i].id
        }
        if err then
          return helpers.yield_error(err)
        end

        ssl_certificates[i].snis = setmetatable({}, cjson.empty_array_mt)

        for j = 1, #rows do
          table.insert(ssl_certificates[i].snis, rows[j].name)
        end

        -- FIXME: remove and stick to previous `empty_array_mt` metatable
        -- assignment once https://github.com/openresty/lua-cjson/pull/16
        -- is included in the OpenResty release we use.
        if #ssl_certificates[i].snis == 0 then
          ssl_certificates[i].snis = cjson.empty_array
        end
      end

      return helpers.responses.send_HTTP_OK({
        data = #ssl_certificates > 0 and ssl_certificates or cjson.empty_array,
        total = #ssl_certificates,
      })
    end,


    PUT = function(self, dao_factory, helpers)
      return crud.put(self.params, dao_factory.ssl_certificates)
    end,
  },


  ["/certificates/:sni_or_uuid"] = {
    before = function(self, dao_factory, helpers)
      if utils.is_valid_uuid(self.params.sni_or_uuid) then
        self.ssl_certificate_id = self.params.sni_or_uuid

      else
        -- get requested SNI

        local row, err = dao_factory.ssl_servers_names:find {
          name = self.params.sni_or_uuid
        }
        if err then
          return helpers.yield_error(err)
        end

        if not row then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end

        -- cache certificate row id

        self.ssl_certificate_id = row.ssl_certificate_id
      end

      self.params.sni_or_uuid = nil
    end,


    GET = function(self, dao_factory, helpers)
      local row, err = dao_factory.ssl_certificates:find {
        id = self.ssl_certificate_id
      }
      if err then
        return helpers.yield_error(err)
      end

      assert(row, "no SSL certificate for given SNI")

      -- add list of other SNIs for this certificate

      row.snis = setmetatable({}, cjson.empty_array_mt)

      local rows, err = dao_factory.ssl_servers_names:find_all {
        ssl_certificate_id = self.ssl_certificate_id
      }
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #rows do
        table.insert(row.snis, rows[i].name)
      end

      -- FIXME: remove and stick to previous `empty_array_mt` metatable
      -- assignment once https://github.com/openresty/lua-cjson/pull/16
      -- is included in the OpenResty release we use.
      if #row.snis == 0 then
        row.snis = cjson.empty_array
      end

      return helpers.responses.send_HTTP_OK(row)
    end,


    PATCH = function(self, dao_factory, helpers)
      return crud.patch(self.params, dao_factory.ssl_certificates, {
        id = self.ssl_certificate_id
      })
    end,


    DELETE = function(self, dao_factory, helpers)
      return crud.delete({
        id = self.ssl_certificate_id
      }, dao_factory.ssl_certificates)
    end,
  }
}
