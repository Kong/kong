local cjson = require "cjson.safe"


local _M = {}


-- The fields field is expected to be an array of fields specs:
-- [
--   {
--     "f1": field_spec1,
--   },
--   {
--     "f2": field_spec2,
--   }
--     ...
-- ]
--
-- Where field_spec accepts any of the new dao's validators (e.g., one_of,
-- min, max, between, etc) and types:
--
-- field_spec1 = {
--   "type": "string",
--   "required": true,
-- }
--
-- The schema validator, however, expects some other fields that will not be
-- specified or used for this plugin purposes
function _M.gen_schema(schema_fields)

  -- decode the user-specified schema as a Lua table so it can be used
  -- with Kong's schema validator
  local fields, err = cjson.decode(schema_fields)
  if err then
    return nil, "failed decoding schema"
  end

  return {
    name = "name",
    primary_key = {"pk"},
    fields = fields,
  }
end


function _M.get_req_body_json()
  ngx.req.read_body()

  local body_data = ngx.req.get_body_data()
  if not body_data or #body_data == 0 then
    return {}
  end

  -- try to decode body data as json
  local body, err = cjson.decode(body_data)
  if err then
    return nil, "request body is not valid JSON"
  end

  return body
end


return _M
