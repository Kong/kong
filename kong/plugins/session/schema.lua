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
            secret = {
              type = "string",
              required = false,
              default = random_string(),
              encrypted = true, -- Kong Enterprise Exclusive. This does nothing in Kong CE
              referenceable = true,
            },
          },
          { storage = { type = "string", one_of = { "cookie", "kong" }, default = "cookie" } },
          { audience = { type = "string", default  = "default" } },
          { idling_timeout = { type = "number", default = 900 } },
          { rolling_timeout = { type = "number", default = 3600 } },
          { absolute_timeout = { type = "number", default  = 86400 } },
          { stale_ttl = { type = "number", default = 10 } },
          { cookie_name = { type = "string", default = "session" } },
          { cookie_path = { type = "string", default = "/" } },
          { cookie_domain = { type = "string" } },
          { cookie_same_site = same_site },
          { cookie_http_only = { type = "boolean", default = true } },
          { cookie_secure = { type = "boolean", default = true } },
          { remember = { type = "boolean", default = false } },
          { remember_cookie_name = { type = "string", default = "remember" } },
          { remember_rolling_timeout = { type = "number", default = 604800 } },
          { remember_absolute_timeout = { type = "number", default = 2592000 } },
          { response_headers = headers },
          { request_headers = headers },
          { logout_methods = logout_methods },
          { logout_query_arg = {  type = "string",  default = "session_logout" } },
          { logout_post_arg = { type = "string", default = "session_logout" } },
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
