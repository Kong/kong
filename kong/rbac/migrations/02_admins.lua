local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"

return {
  up = function (_, _, dao)
    -- add consumer for all RBAC users
      local users, err = dao.rbac_users:find_all()
      if err then
        return err
      end

      local consumer_props = {
        type = enums.CONSUMERS.TYPE.ADMIN,
        status = enums.CONSUMERS.STATUS.APPROVED,
      }

      for _, rbac_user in ipairs(users) do
        consumer_props.username = rbac_user.name
        local consumer, err = dao.consumers:insert(consumer_props)

        if err then
          -- try again - maybe it's a duplicate
          consumer_props.username = rbac_user.name .. utils.uuid()
          consumer, err = dao.consumers:insert(consumer_props)

          if err then
            return err
          end
        end

        -- add key
        local _, err = dao.keyauth_credentials:insert({
          consumer_id = consumer.id,
          key = rbac_user.user_token,
        })

        if err then
          return err
        end

        -- add mapping
        _, err = dao.consumers_rbac_users_map:insert({
          consumer_id = consumer.id,
          user_id = rbac_user.id,
        })

        if err then
          return err
        end
      end
  end
}
