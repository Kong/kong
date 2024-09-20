-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require("kong.meta")
local validator = require("resty.json_threat_protection")


local get_header = kong.request.get_header
local code_message_map = {
  [validator.ERR_MAX_CONTAINER_DEPTH_EXCEEDED] = "at [%s]: The maximum allowed nested depth is exceeded.",
  [validator.ERR_MAX_OBJECT_ENTRY_COUNT_EXCEEDED] = "at [%s]: The maximum number of entries " ..
                                                    "allowed in an object is exceeded.",
  [validator.ERR_MAX_OBJECT_ENTRY_NAME_LENGTH_EXCEEDED] = "at [%s]: The maximum string length " ..
                                                          "allowed in an object's entry name is exceeded.",
  [validator.ERR_MAX_ARRAY_ELEMENT_COUNT_EXCEEDED] = "at [%s]: The maximum number of elements " ..
                                                     "allowed in an array is exceeded.",
  [validator.ERR_MAX_STRING_VALUE_LENGTH_EXCEEDED] = "at [%s]: The maximum length " ..
                                                     "allowed for a string value is exceeded.",
  [validator.ERR_TRAILING_DATA] = "Trailing data.",
  [validator.ERR_INVALID_JSON] = "Invalid JSON.",
  [validator.ERR_NON_UTF8_INPUT] = "Non-UTF8 input.",
}


local JsonThreatProtectionHandler = {
  -- Referencing the priority of xml-threat-protection and
  -- considering the common usage of JSON, set a slightly higher value.
  PRIORITY = 1009,
  VERSION = meta.core_version,
}


function JsonThreatProtectionHandler:access(conf)
  local content_length = tonumber(get_header("content-length"))

  if not content_length or
    (conf.max_body_size > 0 and content_length > conf.max_body_size)
  then
    kong.log.info("Invalid Content-Length: ", content_length)

    if conf.enforcement_mode == "block" then
      return kong.response.error(400, "Invalid Content-Length")
    end
  end

  -- 0 means reading the entire data from temporary files.
  local body, errmsg = kong.request.get_raw_body(conf.max_body_size < 0 and 0 or conf.max_body_size)
  if not body then
    kong.log.info(errmsg)

    return kong.response.error(500)
  end

  local ok, err_code, path = validator.validate(
    body,
    conf.max_container_depth >= 0 and conf.max_container_depth or nil,
    conf.max_object_entry_count >= 0 and conf.max_object_entry_count or nil,
    conf.max_object_entry_name_length >= 0 and conf.max_object_entry_name_length or nil,
    conf.max_array_element_count >= 0 and conf.max_array_element_count or nil,
    conf.max_string_value_length >= 0 and conf.max_string_value_length or nil,
    true, -- enable json path tracing
    true -- enable yielding
  )

  if not ok then
    errmsg = string.format(code_message_map[tonumber(err_code)], path or "")

    kong.log.warn("JSON validate failed: ", errmsg)

    if err_code == validator.ERR_INVALID_JSON or err_code == validator.ERR_NON_UTF8_INPUT then
      return kong.response.error(400, code_message_map[err_code])
    end

    if conf.enforcement_mode == "block" then
      return kong.response.error(conf.error_status_code, conf.error_message)
    end
  end

end


return JsonThreatProtectionHandler
