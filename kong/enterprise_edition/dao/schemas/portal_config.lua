local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local singletons = require "kong.singletons"

return {
  table = "portal_config",
  primary_key = { "id" },
  workspaceable = true,
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    portal_auth = {
      type = "string",
    },
    portal_auth_config = {
      type = "string",
    },
    portal_auto_approve = {
      type = "boolean",
      required = true,
    },
    portal_token_exp = {
      type = "number",
      required = true,
    },
    portal_invite_email = {
      type = "boolean",
      required = true,
    },
    portal_access_request_email = {
      type = "boolean",
      required = true,
    },
    portal_approved_email = {
      type = "boolean",
      required = true,
    },
    portal_reset_email = {
      type = "boolean",
      required = true,
    },
    portal_reset_success_email = {
      type = "boolean",
      required = true,
    },
    portal_emails_from = {
      type = "string",
    },
    portal_emails_reply_to = {
      type = "string",
    },
  },
}
