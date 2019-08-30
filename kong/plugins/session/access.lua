local constants = require "kong.constants"
local session = require "kong.plugins.session.session"
local kong = kong

local _M = {}


local function load_consumer(consumer_id)
  local result, err = kong.db.consumers:select { id = consumer_id }
  if not result then
    return nil, err
  end
  return result
end


local function authenticate(consumer, credential_id, groups)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  if consumer.custom_id then
    set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer.username then
    set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  else
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  if groups then
    set_header(constants.HEADERS.AUTHENTICATED_GROUPS, table.concat(groups, ", "))
    ngx.ctx.authenticated_groups = groups
  else
    clear_header(constants.HEADERS.AUTHENTICATED_GROUPS)
  end

  if credential_id then
    local credential = {id = credential_id or consumer.id, consumer_id = consumer.id}
    set_header(constants.HEADERS.ANONYMOUS, true)
    kong.client.authenticate(consumer, credential)

    return
  end

  kong.client.authenticate(consumer, nil)
end


function _M.execute(conf)
  local s = session.open_session(conf)

  if not s.present then
    kong.log.debug("session not present")
    return
  end

  -- check if incoming request is trying to logout
  if session.logout(conf) then
    kong.log.debug("session logging out")
    s:destroy()
    return kong.response.exit(200)
  end


  local cid, credential, groups = session.retrieve_session_data(s)

  local consumer_cache_key = kong.db.consumers:cache_key(cid)
  local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                       load_consumer, cid)

  if err then
    kong.log.err("could not load consumer: ", err)
    return
  end

  -- destroy sessions with invalid consumer_id
  if not consumer then
    kong.log.debug("failed to find consumer, destroying session")
    return s:destroy()
  end

  s:start()

  authenticate(consumer, credential, groups)

  kong.ctx.shared.authenticated_session = s
end


return _M
