local crud = require "kong.api.crud_helpers"

return {
  ["/consumers/:username_or_id/basic-auth/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.basicauth_credentials)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.basicauth_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.basicauth_credentials, function(credential)
        crud.portal_crud.insert_credential(credential, 'basic-auth')
      end)
    end
  },
  ["/consumers/:username_or_id/basic-auth/:credential_username_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local credentials, err = crud.find_by_id_or_field(
        dao_factory.basicauth_credentials,
        { consumer_id = self.params.consumer_id },
        ngx.unescape_uri(self.params.credential_username_or_id),
        "username"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
      self.params.credential_username_or_id = nil

      self.basicauth_credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.basicauth_credential)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.basicauth_credentials, self.basicauth_credential,
        function(credential)
          crud.portal_crud.update_credential(credential)
      end)
    end,

    DELETE = function(self, dao_factory)
      crud.portal_crud.delete_credential(self.basicauth_credential.id)
      crud.delete(self.basicauth_credential, dao_factory.basicauth_credentials)
    end
  },
  ["/basic-auths/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.basicauth_credentials)
    end
  },
  ["/basic-auths/:credential_username_or_id/consumer"] = {
    before = function(self, dao_factory, helpers)
      local credentials, err = crud.find_by_id_or_field(
        dao_factory.basicauth_credentials,
        nil,
        ngx.unescape_uri(self.params.credential_username_or_id),
        "username"
      )

      self.params.credential_username_or_id = nil
      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.username_or_id = credentials[1].consumer_id
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory,helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end
  }
}
