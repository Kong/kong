-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ffi = require "ffi"
local ngx = ngx

ffi.cdef[[
  typedef enum {
    ERROR_NO_ERROR = 0,
    ERROR_LICENSE_PATH_NOT_SET,
    ERROR_INTERNAL_ERROR,
    ERROR_OPEN_LICENSE_FILE,
    ERROR_READ_LICENSE_FILE,
    ERROR_INVALID_LICENSE_JSON,
    ERROR_INVALID_LICENSE_FORMAT,
    ERROR_VALIDATION_PASS,
    ERROR_VALIDATION_FAIL,
    ERROR_LICENSE_EXPIRED,
    ERROR_INVALID_EXPIRATION_DATE,
    ERROR_GRACE_PERIOD,
  } validation_error_t;

  validation_error_t validate_kong_license_data(const char* license);
]]

local liblicense_utils_loaded, liblicense_utils = pcall(ffi.load, "license_utils")

local _M = {}

local function license_validation_can_proceed()
  -- Check the distribution constants to determine dev vs release
  local dist_constants = require "kong.enterprise_edition.distributions_constants"

  --[[
    If the license cannot be loaded and this is a release build then the
    license validation cannot proceed; every other combination is allowed for
    local development without the library
  ]]
  if dist_constants.release and not liblicense_utils_loaded then
    return false
  end

  return true
end

local function validate_kong_license(license)
  -- Always favor library over the development logic
  if liblicense_utils_loaded then
    -- Handle validation using the C library
    local error = liblicense_utils.validate_kong_license_data(license)
    ngx.log(ngx.DEBUG, "Using liblicense_utils shared library: " , error)
    return error
  else
    local validation_can_proceed = license_validation_can_proceed
    if not validation_can_proceed then
      return "ERROR_INTERNAL_ERROR"
    end

    --[[
      This is only being used for local development and uses the real FFI
      function call when built with kong-distributions. It can be used to
      simulate different errors during testing by naming the variable name being
      passed in the appropriate key. If there is not match, then the returned
      value is always ERROR_VALIDATION_PASS.
    ]]
    local invalid_errors = {
      ["no_error"] = "ERROR_NO_ERROR", -- 0
      ["license_path_not_set"] = "ERROR_LICENSE_PATH_NOT_SET", -- 1
      ["internal_error"] = "ERROR_INTERNAL_ERROR", -- 2
      ["open_license_file"] = "ERROR_OPEN_LICENSE_FILE", -- 3
      ["read_license_file"] = "ERROR_READ_LICENSE_FILE", -- 4
      ["invalid_license_json"] = "ERROR_INVALID_LICENSE_JSON", -- 5
      ["invalid_license_format"] = "ERROR_INVALID_LICENSE_FORMAT", -- 6
      ["validation_fail"] = "ERROR_VALIDATION_FAIL", -- 8
      ["license_expired"] = "ERROR_LICENSE_EXPIRED", -- 9
      ["invalid_expiration_date"] = "ERROR_INVALID_EXPIRATION_DATE", -- 10
      ["grace_period"] = "ERROR_GRACE_PERIOD", -- 11
    }

    local passed_in_variable_name = debug.getlocal(2, 1)
    local error = "ERROR_VALIDATION_PASS" -- 7
    for key, value in pairs(invalid_errors) do
      if key == passed_in_variable_name then
        error = value
        break
      end
    end

    ngx.log(ngx.WARN, "Using development (e.g. not a release) license validation: ", error)
    return error
  end
end

_M.license_validation_can_proceed = license_validation_can_proceed
_M.validate_kong_license = validate_kong_license

return _M