-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local file_helpers = require "kong.portal.file_helpers"

local match = string.match

local function validate_path(path)
  if path:sub(1, 1) == "/" then
    return nil, "path must not begin with a slash '/'"
  end

  if match(path, "//") then
    return false, "path must not contain '//'"
  end

  local ext = match(path, "%.(%w+)$")
  if not ext then
    return false, "path must end with a file extension"
  end

  if file_helpers.is_content_path(path) then
    local ok, err = file_helpers.is_valid_content_ext(path)
    if not ok then
      return nil, err
    end

  elseif file_helpers.is_spec_path(path) then
    local ok, err = file_helpers.is_valid_spec_ext(path)
    if not ok then
      return nil, err
    end

  elseif not file_helpers.is_html_ext(path) and
         (file_helpers.is_layout_path(path) or
         file_helpers.is_partial_path(path)) then
      return nil, "layouts and partials must end with extension '.html'"
  end

  return true
end

local function get_keys(table)
  local key_string = ""
  for key in pairs(table) do
    key_string = key_string .. ", " .. key
  end

  return key_string
end

local function is_match(token, view)
  local match_token = "{{%s*" .. token .. "%s*}}"
  return match(view, match_token)
end


local email_paths = {
  ["emails/invite.txt"] = {
    "portal.url",
  },
  ["emails/request-access.txt"] = {
    "portal.url",
    "email.developer_email"
  },
  ["emails/approved-access.txt"] = {
    "portal.url",
  },
  ["emails/password-reset.txt"] = {
    "portal.url",
    {"email.token", "email.reset_url"}
  },
  ["emails/password-reset-success.txt"] = {
    "portal.url",
  },
  ["emails/account-verification-approved.txt"] = {
    "portal.url",
  },
  ["emails/account-verification-pending.txt"] = {
    "portal.url",
  },
  ["emails/account-verification.txt"] = {
    "portal.url",
    {"email.token", "email.verify_url"},
    {"email.token", "email.invalidate_url"}
  },
}

return {
  name = "files",
  primary_key = {"id"},
  workspaceable = true,
  endpoint_key = "path",
  dao = "kong.db.dao.files",
  db_export = false,
  fields = {
    {id = typedefs.uuid},
    {created_at = typedefs.auto_timestamp_s},
    {
      path = {
        type = "string",
        required = true,
        unique = true,
        custom_validator = validate_path
      }
    },
    {contents = {type = "string", len_min = 0, required = true}},
    {checksum = {type = "string", len_min = 0}}
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = {"path", "contents"},
        fn = function(entity)
          local entity_path = entity.path

          if entity_path:sub(1, #"emails/") ~= "emails/" then
            return true
          end

          if email_paths[entity_path] == nil then
            return nil, "only: " .. get_keys(email_paths) .. " email paths supported"
          end

          local tokens = email_paths[entity_path]
          for _, token in ipairs(tokens) do
            if type(token) == "table" then
              -- only needs to match one
              local ok = false
              for _, or_token in ipairs(token) do
                if is_match(or_token, entity.contents) then
                  ok = true
                end
              end
              if not ok then
                return nil, entity_path .. " template must contain either '{{" ..
                          token[1] .. "}}' or '{{" .. token[2] .. "}}' tokens"
              end

            else
              local ok = is_match(token, entity.contents)
              if not ok then
                return nil, entity_path .. " template must contain token: '{{" .. token .. "}}'"
              end
            end
          end

          return true
        end
      }
    }
  }
}
