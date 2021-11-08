-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- see: https://konghq.atlassian.net/browse/FT-1982
-- local function validate_specification(given_value, given_config)
--   -- TODO: how to enable it in current plugin development stack?
--   local api_specification_filename = given_config.api_specification_filename
--   local api_specification = given_config.api_specification
--   if (api_specification_filename  == nil or api_specification_filename  == '') and (api_specification == nil or api_specification == '') then
--     return false, "You need to define either api_specification_filename or api_specification"
--   end

--   if api_specification == nil or api_specification == '' then
--     if kong.db == nil then
--       return false, "API Specification file api_specification_filename defined which is not supported in dbless mode - not supported. Use api_specification instead"
--     end
--   end
-- end

return {
  name = "mocking",
  fields = {
    { config = {
      type = "record",
      fields = {
        { api_specification_filename = { type = "string", required = false } },
        { api_specification = { type = "string", required = false } },
        { random_delay = { type = "boolean", default = false } },
        { max_delay_time = { type = "number", default = 1 } },
        { min_delay_time = { type = "number", default = 0.001 } },
      }
    } },
  },

}
