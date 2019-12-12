local function validate_fn_or_string(fn_or_str)
  if type(fn_or_str) == "function"
  or type(fn_or_str) == "string" and #fn_or_str > 0
  then
    return true
  end

  return nil, "expected a non-empty string or function"
end


local strat_migration = {
  { up = { type = "any",
           required = true,
           custom_validator = validate_fn_or_string,
         },
  },
  { teardown = { type = "function" } },
}


return {
  name = "migration",
  fields = {
    { name      = { type = "string", required = true } },
    { postgres  = { type = "record", required = true, fields = strat_migration } },
    { cassandra = { type = "record", required = true, fields = strat_migration } },
  },
}
