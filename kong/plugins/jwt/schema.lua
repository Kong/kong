local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end

local function check_positive(v)
  if v < 0 then
    return false, "should be 0 or greater"
  end

  return true
end

return {
  no_consumer = true,
  fields = {
    uri_param_names = {type = "array", default = {"jwt"}},
    cookie_names = {type = "array", default = {}},
    key_claim_name = {type = "string", default = "iss"},
    secret_is_base64 = {type = "boolean", default = false},
    claims_to_verify = {type = "array", enum = {"exp", "nbf"}},
    anonymous = {type = "string", default = "", func = check_user},
    run_on_preflight = {type = "boolean", default = true},
    maximum_expiration = {type = "number", default = 0, func = check_positive},
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if plugin_t.maximum_expiration ~= nil
       and plugin_t.maximum_expiration > 0
    then
      local has_exp

      if plugin_t.claims_to_verify then
        for index, value in ipairs(plugin_t.claims_to_verify) do
          if value == "exp" then
            has_exp = true
            break
          end
        end
      end

      if not has_exp then
        return false, Errors.schema "claims_to_verify must contain 'exp' when specifying maximum_expiration"
      end
    end

    return true
  end
}
