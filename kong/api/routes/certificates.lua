local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


local function create_certificate(self, dao_factory, helpers)
  local snis
  if type(self.params.snis) == "string" then
    snis = utils.split(self.params.snis, ",")
  end

  self.params.snis = nil

  if snis then
    -- dont add the certificate or any snis if we have an SNI conflict
    -- its fairly inefficient that we have to loop twice over the datastore
    -- but no support for OR queries means we gotsta!
    local snis_in_request = {}

    for _, sni in ipairs(snis) do
      if snis_in_request[sni] then
        return helpers.responses.send_HTTP_CONFLICT("duplicate SNI in " ..
                                                    "request: " .. sni)
      end
      local cnt, err = dao_factory.ssl_servers_names:run_with_ws_scope({},
        dao_factory.ssl_servers_names.count, {
        name = sni,
      })

      if err then
        return helpers.yield_error(err)
      end

      if cnt > 0 then
        -- Note: it could be that the SNI is not associated with any
        -- certificate, but we don't handle this case. (for PostgreSQL
        -- only, as C* requires a cert_id for its partition key).
        return helpers.responses.send_HTTP_CONFLICT("SNI already exists: " ..
                                                    sni)
      end

      snis_in_request[sni] = true
    end
  end

  local ssl_cert, err = dao_factory.ssl_certificates:insert(self.params)
  if err then
    return helpers.yield_error(err)
  end

  ssl_cert.snis = setmetatable({}, cjson.empty_array_mt)

  -- insert SNIs if given

  if snis then
    for i, sni in ipairs(snis) do
      local ssl_server_name = {
        name                = sni,
        ssl_certificate_id  = ssl_cert.id,
      }

      local row, err = dao_factory.ssl_servers_names:insert(ssl_server_name)
      if err then
        return helpers.yield_error(err)
      end

      ssl_cert.snis[i] = row.name
    end
  end

  return helpers.responses.send_HTTP_CREATED(ssl_cert)
end


local function update_certificate(self, dao_factory, helpers)
   -- check if exists
   local ssl_cert, err = dao_factory.ssl_certificates:find {
    id = self.params.id
  }
  if err then
    return helpers.yield_error(err)
  end

  if not ssl_cert then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  local snis
  if type(self.params.snis) == "string" then
    snis = utils.split(self.params.snis, ",")

  elseif self.params.snis == ngx.null then
    snis = {}
  end

  self.params.snis = nil

  local snis_in_request = {} -- check for duplicate snis in the request
  local snis_in_db = {} -- avoid db insert if sni is already present in db

  -- if snis field present
  -- 1. no duplicate snis should be present in the request
  -- 2. check if any sni in the request is using a cert
  --    other than the one being updated

  if snis then
    for _, sni in ipairs(snis) do
      if snis_in_request[sni] then
        return helpers.responses.send_HTTP_CONFLICT("duplicate SNI in " ..
                                                    "request: " .. sni)
      end

      local sni_in_db, err = dao_factory.ssl_servers_names:find {
        name = sni,
      }
      if err then
        return helpers.yield_error(err)
      end

      if sni_in_db then
        if sni_in_db.ssl_certificate_id ~= ssl_cert.id then
          return helpers.responses.send_HTTP_CONFLICT(
            "SNI '" .. sni .. "' already associated with existing " ..
            "certificate (" .. sni_in_db.ssl_certificate_id .. ")"
          )
        end

        snis_in_db[sni] = true
      end

      snis_in_request[sni] = true
    end
  end

  local old_snis, err = dao_factory.ssl_servers_names:find_all {
    ssl_certificate_id = ssl_cert.id,
  }
  if err then
    return helpers.yield_error(err)
  end

  -- update certificate if necessary
  if self.params.key or self.params.cert then
    self.params.created_at = ssl_cert.created_at

    ssl_cert, err = dao_factory.ssl_certificates:update(self.params, {
      id = self.params.id,
    }, { full = true })
    if err then
      return helpers.yield_error(err)
    end
  end

  ssl_cert.snis = setmetatable({}, cjson.empty_array_mt)

  if not snis then
    for i = 1, #old_snis do
      ssl_cert.snis[i] = old_snis[i].name
    end

    return helpers.responses.send_HTTP_OK(ssl_cert)
  end

  -- insert/delete SNIs into db if snis field was present in the request
  for i, sni in ipairs(snis) do
    if not snis_in_db[sni] then
      local ssl_server_name = {
        name                = sni,
        ssl_certificate_id  = ssl_cert.id,
      }

      local _, err = dao_factory.ssl_servers_names:insert(ssl_server_name)
      if err then
        return helpers.yield_error(err)
      end
    end

    ssl_cert.snis[i] = sni
  end

  -- delete snis which should no longer use ssl_cert
  for i = 1, #old_snis do
    if not snis_in_request[old_snis[i].name] then
      -- ignoring error
      -- if we want to return an error here
      -- to return 4xx here, the current transaction needs to be
      -- rolled back else we risk an invalid state and confusing
      -- the user
      dao_factory.ssl_servers_names:delete({
        name = old_snis[i].name,
      })
    end
  end

  return helpers.responses.send_HTTP_OK(ssl_cert)
end


return {
  ["/certificates/"] = {
    POST = function(self, dao_factory, helpers)
      create_certificate(self, dao_factory, helpers)
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
          ssl_certificates[i].snis[j] = rows[j].name
        end
      end

      return helpers.responses.send_HTTP_OK({
        data = #ssl_certificates > 0 and ssl_certificates or cjson.empty_array,
        total = #ssl_certificates,
      })
    end,


    PUT = function(self, dao_factory, helpers)
      -- no id present, behaviour should be same as POST
      if not self.params.id then
        create_certificate(self, dao_factory, helpers)
        return -- avoid tail call
      end

      -- id present in body
      update_certificate(self, dao_factory, helpers)
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

        if not row or not row.ssl_certificate_id then
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

      if not row then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- add list of other SNIs for this certificate

      row.snis = setmetatable({}, cjson.empty_array_mt)

      local rows, err = dao_factory.ssl_servers_names:find_all {
        ssl_certificate_id = self.ssl_certificate_id
      }
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #rows do
        row.snis[i] = rows[i].name
      end

      return helpers.responses.send_HTTP_OK(row)
    end,


    PATCH = function(self, dao_factory, helpers)
      self.params.id = self.ssl_certificate_id
      update_certificate(self, dao_factory, helpers)
    end,


    DELETE = function(self, dao_factory, helpers)
      return crud.delete({
        id = self.ssl_certificate_id
      }, dao_factory.ssl_certificates)
    end,
  }
}
