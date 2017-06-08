local json = require "cjson.safe"
local crud = require "kong.api.crud_helpers"

return {
  ["/openid-connect/issuers/"] = {
    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_issuers, function(row)
        local configuration = row.configuration
        if configuration then
          configuration = json.decode(configuration)
          if configuration then
            row.configuration = configuration

          else
            configuration = {}
          end
        end

        local keys = row.keys
        if keys then
          keys = json.decode(keys)
          if keys then
            row.keys = keys

          else
            keys = {}
          end
        end
      end)
    end,
  },
  ["/openid-connect/issuers/:id"] = {
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_issuers)
    end
  },
}
