local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/:username_or_id/metadata/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.metadata_keyvaluestore)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.metadata_keyvaluestore)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.metadata_keyvaluestore)
    end
  }
}
