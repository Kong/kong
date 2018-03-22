local jwt_schema = require "kong.plugins.jwt.schema"

describe("Plugin: jwt (schema)", function()
   local ok, res
   ok = jwt_schema.self_check(nil, {maximum_expiration = -1}, nil, true)
   assert.is_true(ok) 

   ok, res = jwt_schema.self_check(nil, {maximum_expiration = 300}, nil, true)
   assert.is_false(ok) 
   assert.is_equals(res.message, "to set maximum_expiration, you need to add 'exp' in claims_to_verify") 

   ok = jwt_schema.self_check(nil, {maximum_expiration = 300, claims_to_verify = {}}, nil, true)
   assert.is_false(ok) 
   assert.is_equals(res.message, "to set maximum_expiration, you need to add 'exp' in claims_to_verify") 

   ok = jwt_schema.self_check(nil, {maximum_expiration = 300, claims_to_verify = {"exp"}}, nil, true)
   assert.is_true(ok) 

   ok = jwt_schema.self_check(nil, {maximum_expiration = -1, claims_to_verify = {"iss", "exp", "nbf"}}, nil, true)
   assert.is_true(ok) 
end)
