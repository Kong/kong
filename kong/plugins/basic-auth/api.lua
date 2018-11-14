local crud = require "kong.api.crud_helpers"
local ee_crud = require "kong.enterprise_edition.crud_helpers"
local enums   = require "kong.enterprise_edition.dao.enums"

return {
  ["/consumers/:username_or_id/basic-auth/"] = {
    before = function(self, dao_factory, helpers)
      ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.basicauth_credentials)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.basicauth_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.basicauth_credentials,
                crud.portal_crud.insert_credential('basic-auth'))
    end
  },
  ["/developers/:email_or_id/basic-auth/"] = {
    before = function(self, dao_factory, helpers)
      self.params.email_or_id = ngx.unescape_uri(self.params.email_or_id)
      ee_crud.find_developer_by_email_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      self.params.plugin = 'basic-auth'
      self.params.consumer_type = enums.CONSUMERS.TYPE.PROXY
      crud.paginated_set(self, dao_factory.credentials, function (row)
        return row.credential_data
      end)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.basicauth_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.basicauth_credentials,
                crud.portal_crud.insert_credential('basic-auth'))
    end
  },
  ["/consumers/:username_or_id/basic-auth/:credential_username_or_id"] = {
    before = function(self, dao_factory, helpers)
      ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
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
          crud.portal_crud.update_credential)
    end,

    DELETE = function(self, dao_factory)
      crud.portal_crud.delete_credential(self.basicauth_credential)
      crud.delete(self.basicauth_credential, dao_factory.basicauth_credentials)
    end
  },
  ["/developers/:email_or_id/basic-auth/:credential_username_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.email_or_id = ngx.unescape_uri(self.params.email_or_id)
      ee_crud.find_developer_by_email_or_id(self, dao_factory, helpers)
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
          crud.portal_crud.update_credential)
    end,

    DELETE = function(self, dao_factory)
      crud.portal_crud.delete_credential(self.basicauth_credential)
      crud.delete(self.basicauth_credential, dao_factory.basicauth_credentials)
    end
  },
  ["/basic-auths/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self,
                         dao_factory.basicauth_credentials,
                         ee_crud.post_process_credential)
    end
  },
  ["/basic-auths/:credential_username_or_id/:type"] = {
    before = function(self, dao_factory, helpers)
      local credentials, err = crud.find_by_id_or_field(
        dao_factory.basicauth_credentials,
        nil,
        ngx.unescape_uri(self.params.credential_username_or_id),
        "username"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.credential_username_or_id = nil

      if self.params.type == 'developer' then
        self.params.email_or_id = credentials[1].consumer_id
        ee_crud.find_developer_by_email_or_id(self, dao_factory, helpers)
      end

      if self.params.type == 'consumer' then
        self.params.username_or_id = credentials[1].consumer_id
        ee_crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      end

      if not self.consumer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory,helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end
  },
}
