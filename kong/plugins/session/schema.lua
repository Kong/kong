local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local utils = require "kong.tools.utils"


local char = string.char
local rand = math.random
local encode_base64 = ngx.encode_base64


local same_site = Schema.define {
  type = "string",
  default = "Strict",
  one_of = {
    "Strict",
    "Lax",
    "None",
    "Default",
  },
}


local headers = Schema.define({
  type     = "set",
  elements = {
    type = "string",
    one_of = {
      "id",
      "audience",
      "subject",
      "timeout",
      "idling-timeout",
      "rolling-timeout",
      "absolute-timeout",
    },
  },
})


local logout_methods = Schema.define({
  type = "set",
  elements = {
    type = "string",
    one_of = { "GET", "POST", "DELETE" },
  },
  default = { "POST", "DELETE" },
})


--- kong.utils.random_string with 32 bytes instead
-- @returns random string of length 44
local function random_string()
  return encode_base64(utils.get_rand_bytes(32, true))
                       :gsub("/", char(rand(48, 57)))  -- 0 - 10
                       :gsub("+", char(rand(65, 90)))  -- A - Z
                       :gsub("=", char(rand(97, 122))) -- a - z
end


return {
  name = "session",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          {
            secret = { description = "The secret that is used in keyed HMAC generation.", type = "string",
              required = false,
              default = random_string(),
              encrypted = true, -- Kong Enterprise Exclusive. This does nothing in Kong CE
              referenceable = true,
            },
          },
          { storage = { description = "Determines where the session data is stored. `kong`: Stores encrypted session data into Kong's current database\nstrategy; the cookie will not contain any session data. `cookie`: Stores encrypted\nsession data within the cookie itself.", type = "string", one_of = { "cookie", "kong" }, default = "cookie" } },
          { audience = { description = "The session audience, which is the intended target application. For example `\"my-application\"`.", type = "string", default  = "default" } },
          { idling_timeout = { description = "The session cookie idle time, in seconds.", type = "number", default = 900 } },
          { rolling_timeout = { description = "The session cookie rolling timeout, in seconds.\nSpecifies how long the session can be used until it needs to be renewed.", type = "number", default = 3600 } },
          { absolute_timeout = { description = "The session cookie absolute timeout, in seconds.\nSpecifies how long the session can be used until it is no longer valid.", type = "number", default  = 86400 } },
          { stale_ttl = { description = "The duration, in seconds, after which an old cookie is discarded, starting from the moment\nwhen the session becomes outdated and is replaced by a new one.", type = "number", default = 10 } },
          { cookie_name = { description = "The name of the cookie.", type = "string", default = "session" } },
          { cookie_path = { description = "The resource in the host where the cookie is available.", type = "string", default = "/" } },
          { cookie_domain = { description = "The domain with which the cookie is intended to be exchanged.", type = "string" } },
          { cookie_same_site = same_site, description = "Determines whether and how a cookie may be sent with cross-site requests.\n\n* `Strict`: The browser sends cookies only if the request originated from the website that set the cookie.\n* `Lax`: Same-site cookies are withheld on cross-domain subrequests, but are sent when a user navigates\nto the URL from an external site, for example, by following a link. \n* `None` or `off`: Disables the same-site attribute so that a cookie may be sent with cross-site requests. \n`None` requires the Secure attribute (`cookie_secure`) in latest browser versions. For more info, see the\n[SameSite cookies docs on MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite)." },
          { cookie_http_only = { description = "Applies the `HttpOnly` tag so that the cookie is sent only to a server. See the\n[Restrict access to cookies docs on MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies#Restrict_access_to_cookies).", type = "boolean", default = true } },
          { cookie_secure = { description = "Applies the Secure directive so that the cookie may be sent to the server only with an encrypted\nrequest over the HTTPS protocol. See the\n[Restrict access to cookies docs on MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies#Restrict_access_to_cookies).", type = "boolean", default = true } },
          { remember = { description = "Enables or disables persistent sessions.", type = "boolean", default = false } },
          { remember_cookie_name = { description = "Persistent session cookie name. Use with the `remember` configuration parameter.", type = "string", default = "remember" } },
          { remember_rolling_timeout = { description = "The persistent session rolling timeout window, in seconds.", type = "number", default = 604800 } },
          { remember_absolute_timeout = { description = "The persistent session absolute timeout limit, in seconds.", type = "number", default = 2592000 } },
          { response_headers = headers, { description = "List of information to include, as headers, in the response to the downstream.\n\n\nAccepted values are: `id`, `audience`, `subject`, `timeout`, `idling-timeout`, `rolling-timeout`, and\n`absolute-timeout`.\n\nFor example: `{ \"id\", \"timeout\" }` injects both `Session-Id` and `Session-Timeout` in the response headers."}},
          { request_headers = headers },
          { logout_methods = logout_methods },
          { logout_query_arg = { description = "The query argument passed to logout requests.", type = "string",  default = "session_logout" } },
          { logout_post_arg = { description = "The POST argument passed to logout requests. Do not change this property.", type = "string", default = "session_logout" } },
        },
        shorthand_fields = {
          -- TODO: deprecated forms, to be removed in Kong 4.0
          {
            cookie_lifetime = {
              type = "number",
              func = function(value)
                return { rolling_timeout = value }
              end,
            },
          },
          {
            cookie_idletime = {
              type = "number",
              func = function(value)
                if value == nil or value == ngx.null then
                  value = 0
                end
                return { idling_timeout = value }
              end,
            },
          },
          {
            cookie_renew = {
              type = "number",
              func = function()
                -- session library 4.0.0 calculates this
                ngx.log(ngx.INFO, "[session] cookie_renew option does not exists anymore")
              end,
            },
          },
          {
            cookie_discard = {
              type = "number",
              func = function(value)
                return { stale_ttl = value }
              end,
            }
          },
          {
            cookie_samesite = {
              type = "string",
              func = function(value)
                if value == "off" then
                  value = "Lax"
                end
                return { cookie_same_site = value }
              end,
            },
          },
          {
            cookie_httponly = {
              type = "boolean",
              func = function(value)
                return { cookie_http_only = value }
              end,
            },
          },
          {
            cookie_persistent = {
              type = "boolean",
              func = function(value)
                return { remember = value }
              end,
            }
          },
        },
      },
    },
  },
}
