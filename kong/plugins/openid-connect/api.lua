local json = require "cjson.safe"
local crud = require "kong.api.crud_helpers"


local function issuer(row)
  local configuration = row.configuration
  if configuration then
    configuration = json.decode(configuration)
    if configuration then
      row.configuration = configuration

    else
      row.configuration = {}
    end
  end

  local keys = row.keys
  if keys then
    keys = json.decode(keys)
    if keys then
      row.keys = keys

    else
      row.keys = {}
    end
  end

  row.secret = nil

  return row
end


return {
  ["/openid-connect/issuers/"] = {
    resource = "openid-connect",

    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_issuers, issuer)
    end,
  },
  ["/openid-connect/issuers/:id"] = {
    resource = "openid-connect",

    GET = function(self, dao)
      crud.get({ id = self.params.id }, dao.oic_issuers, issuer)
    end,
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_issuers)
    end
  },
}
