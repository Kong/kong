-- Common constants
local constants = {
  -- Lua style pattern, used in schema validation
  REGEX_STATUS_CODE_RANGE = [[^[0-9]+-[0-9]+$]],
  -- PCRE pattern, used in log_handler.lua
  REGEX_SPLIT_STATUS_CODES_BY_DASH = [[(\d\d\d)-(\d\d\d)]],
}

return constants