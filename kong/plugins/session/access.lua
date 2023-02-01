local constants = require "kong.constants"
local kong_session = require "kong.plugins.session.session"


local ngx = ngx
local kong = kong
local concat = table.concat


local _M = {}


local function authenticate(consumer, credential_id, groups)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer.id then
    set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  else
    clear_header(constants.HEADERS.CONSUMER_ID)
  end

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
    set_header(constants.HEADERS.AUTHENTICATED_GROUPS, concat(groups, ", "))
    ngx.ctx.authenticated_groups = groups
  else
    clear_header(constants.HEADERS.AUTHENTICATED_GROUPS)
  end

  local credential
  if credential_id then
    credential = {
      id          = credential_id,
      consumer_id = consumer.id,
    }

    clear_header(constants.HEADERS.ANONYMOUS)

    if constants.HEADERS.CREDENTIAL_IDENTIFIER then
      set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.id)
    end

  else
    set_header(constants.HEADERS.ANONYMOUS, true)

    if constants.HEADERS.CREDENTIAL_IDENTIFIER then
      clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    end
  end

  kong.client.authenticate(consumer, credential)
end


function _M.execute(conf)
  -- check if session exists
  local session, err, exists = kong_session.open_session(conf)
  if not exists then
    if err then
      kong.log.debug("session not present (", err, ")")
    else
      kong.log.debug("session not present")
    end

    return
  end

  -- check if incoming request is trying to logout
  if kong_session.logout(conf) then
    kong.log.debug("session logging out")
    local ok, err = session:logout()
    if not ok then
      if err then
        kong.log.warn("session logout failed (", err, ")")
      else
        kong.log.warn("session logout failed")
      end
    end

    return kong.response.exit(200)
  end

  local consumer_id, credential_id, groups = kong_session.get_session_data(session)

  local consumer_cache_key = kong.db.consumers:cache_key(consumer_id)
  local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                       kong.client.load_consumer, consumer_id)
  if err then
    kong.log.err("could not load consumer: ", err)
    return
  end

  -- destroy sessions with invalid consumer_id
  if not consumer then
    kong.log.debug("failed to find consumer, destroying session")
    local ok, err = session:logout()
    if not ok then
      if err then
        kong.log.warn("session logout failed (", err, ")")
      else
        kong.log.warn("session logout failed")
      end
    end

    return
  end

  local ok, err = session:refresh()
  if not ok then
    if err then
      kong.log.warn("session refresh failed (", err, ")")
    else
      kong.log.warn("session refresh failed")
    end
  end

  session:set_headers()

  kong.ctx.shared.authenticated_session = session

  authenticate(consumer, credential_id, groups)
end


return _M
