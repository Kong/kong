local BasePlugin = require "kong.plugins.base_plugin"
local BindConsumer = require "kong.plugins.ldap-acl.bind_consumer"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"

local LdapAclHandler = BasePlugin:extend()

function LdapAclHandler:new()
  LdapAclHandler.super.new(self, "ldap-acl")
end

function LdapAclHandler:access(conf)
  LdapAclHandler.super.access(self)

  local ldap_authorization = ngx.ctx.authenticated_credential

  if not ldap_authorization then
    return responses.send_HTTP_UNAUTHORIZED()
  end

  if not ldap_authorization.username then
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local bind_consumer = BindConsumer:new { dao = singletons.dao.consumers, cache = cache }

  ngx.log(ngx.DEBUG, "[ldap-acl] bind username between ldap and consumer: ", ldap_authorization.username)
  local consumer = BindConsumer.bind(bind_consumer, ldap_authorization.username)

  if not consumer then
    ngx.log(ngx.ERR, "[ldap-acl] consumer was not found by ldap user: ", ldap_authorization.username)
    return responses.send_HTTP_UNAUTHORIZED()
  end

  ldap_authorization.consumer_id = consumer.id
end

LdapAclHandler.PRIORITY = 999

return LdapAclHandler
