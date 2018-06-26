local enums = require "kong.enterprise_edition.dao.enums"


local _M = {}


function _M.register_resources(dao)
  local _, err = dao.consumer_types:insert({
    id = enums.CONSUMERS.TYPE.PROXY,
    name = 'proxy',
    comment = "Default consumer, used for proxy.",
  })

  if err then
    return err
  end

  local _, err = dao.consumer_types:insert({
    id = enums.CONSUMERS.TYPE.DEVELOPER,
    name = 'developer',
    comment = "Kong Developer Portal consumer.",
  })

  if err then
    return err
  end

  local _, err = dao.consumer_types:insert({
    id = enums.CONSUMERS.TYPE.ADMIN,
    name = 'admin',
    comment = "Admin consumer.",
  })

  if err then
    return err
  end

  for status, id in pairs(enums.CONSUMERS.STATUS) do
    local _, err = dao.consumer_statuses:insert({
      id = id,
      name = status,
    })

    if err then
      return err
    end
  end
end


-- Update all consumers without a "type"
function _M.update_consumers(dao, type)
  local rows, err = dao.consumers:find_all()
  if err then
    return err
  end

  for _, row in ipairs(rows) do
    if not row.type then
      local _, err = dao.consumers:update({ type = type }, { id = row.id })
      if err then
        return err
      end
    end
  end
end


return _M
