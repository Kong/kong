local enums = require "kong.portal.enums"


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


return _M
