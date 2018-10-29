local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"

return {
  table = "consumer_reset_secrets",
  primary_key = { "id" },
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    consumer_id = {
      type = "id",
      foreign = "consumers:id",
      required = true,
    },
    secret = {
      type = "string",
      immutable = true,
      default = utils.random_string,
      required = true,
    },
    status = {
      type = "integer",
      required = true,
      default = enums.TOKENS.STATUS.PENDING,
    },
    client_addr = {
      type = "string",
      immutable = true,
      required = true,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    updated_at = {
      type = "timestamp",
      required = true,
      dao_insert_value = true,
    },
  },
}
