return require("kong.tools.sandbox.require.lua") .. [[
kong.db.schema.typedefs kong.tools.redis.schema

kong.enterprise_edition.tools.redis.v2 kong.enterprise_edition.tools.redis.v2.schema
]]
