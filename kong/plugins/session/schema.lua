local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local utils = require("kong.tools.utils")
local char = string.char
local rand = math.random
local encode_base64 = ngx.encode_base64

local samesite = Schema.define {
  type = "string",
  default = "Strict",
  one_of = {
    "Strict",
    "Lax",
    "off",
  }
}


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
    { config = {
        type = "record",
        fields = {
          { consumer = typedefs.no_consumer },
          {
            secret = {
              type = "string",
              required = false,
              default = random_string(),
            },
          },
          { cookie_name = { type = "string", default = "session" } },
          { cookie_lifetime = { type = "number", default = 3600 } },
          { cookie_renew = { type = "number", default = 600 } },
          { cookie_path = { type = "string", default = "/" } },
          { cookie_domain = { type = "string" } },
          { cookie_samesite = samesite },
          { cookie_httponly = { type = "boolean", default = true } },
          { cookie_secure = { type = "boolean", default = true } },
          { cookie_discard = { type = "number", default = 10 } },
          {
            storage = {
              required = false,
              type = "string",
              one_of = {
                "cookie",
                "kong",
              },
              default = "cookie",
            }
          },
          {
            logout_methods = {
              type = "array",
              elements = {
                type = "string",
                one_of = { "GET", "POST", "DELETE" },
              },
              default = { "POST", "DELETE" },
            }
          },
          {
            logout_query_arg = {
              required = false,
              type = "string",
              default = "session_logout",
            }
          },
          {
            logout_post_arg = {
              required = false,
              type = "string",
              default = "session_logout",
            },
          },
        },
      },
    },
  },
}
