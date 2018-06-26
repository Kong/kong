local crud  = require "kong.api.crud_helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local utils = require "kong.tools.utils"

return {
  ["/admins"] = {
    before = function(self, dao_factory)
      self.params.type = enums.CONSUMERS.TYPE.ADMIN
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    POST = function(self, dao_factory, helpers)
      local responses = helpers.responses

      crud.post({
        username  = self.params.username,
        custom_id = self.params.custom_id,
        type      = self.params.type,
        status    = enums.CONSUMERS.STATUS.APPROVED,
      }, dao_factory.consumers, function(consumer)
        local name = "user"

        if consumer.username then
          name = name .. "-" .. consumer.username
        end

        if consumer.custom_id then
          name = name .. "-" .. consumer.custom_id
        end

        crud.post({
          name = name,
          user_token = utils.uuid(),
          comment = "User generated on creation of Admin.",
        }, dao_factory.rbac_users,
        function (rbac_user)
          crud.post({
            consumer_id = consumer.id,
            user_id = rbac_user.id,
          }, dao_factory.consumers_rbac_users_map,
          function()
            return responses.send_HTTP_OK({
              rbac_user = rbac_user,
              consumer = consumer
            })
          end)

          return responses.send_HTTP_INTERNAL_SERVER_ERROR(
            "Error mapping rbac user ".. rbac_user.id
                                      .. " to consumer " .. consumer.id)
        end)

        return responses.send_HTTP_CREATED({ consumer = consumer })
      end)

      return responses.send_HTTP_INTERNAL_SERVER_ERROR("Error creating admin")
    end,
  },

  ["/admins/:username_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)

      if self.consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      -- Lookup the rbac_user<->consumer map
      local maps, err = dao_factory.consumers_rbac_users_map:find_all({
        consumer_id = self.consumer.id
      })

      if err then
        helpers.yield_error(err)
      end

      local consumer_user = maps[1]

      if not consumer_user then
        ngx.log(ngx.ERR, "No RBAC user relation found for admin consumer "
                         .. self.consumer.id)
        helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      -- Find the rbac_user associated with the consumer
      local users, err = dao_factory.rbac_users:find_all({
        id = consumer_user.user_id
      })

      if err then
        helpers.yield_error(err)
      end

      -- Set the rbac_user on the consumer entity
      local rbac_user = users[1]

      if not rbac_user then
        ngx.log(ngx.ERR, "No RBAC user relation found for admin consumer "
                         .. consumer_user.consumer_id .. " and rbac user "
                         .. consumer_user.user_id)
        helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      self.consumer.rbac_user = rbac_user

      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.consumers, self.consumer)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.consumer, dao_factory.consumers)
    end
  },
}
