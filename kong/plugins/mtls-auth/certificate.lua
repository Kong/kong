--- Copyright 2019 Kong Inc.
local plugin_iterator = require "kong.runloop.handler".get_plugins_iterator


local _M = {}


local kong = kong


function _M.execute()
  if plugin_iterator().map["mtls-auth"] then
    -- TODO: improve detection of ennoblement once we have DAO functions
    -- to filter plugin configurations based on plugin name

    kong.log.debug("enabled, will request certificate from client")

    local res, err = kong.client.tls.request_client_certificate()
    if not res then
      kong.log.error("unable to request client to present its certificate: ",
                     err)
    end

    -- disable session resumption to prevent inability to access client
    -- certificate in later phases
    res, err = kong.client.tls.disable_session_reuse()
    if not res then
      kong.log.error("unable to disable session reuse for client certificate: ",
                     err)
    end
  end
end


return _M
