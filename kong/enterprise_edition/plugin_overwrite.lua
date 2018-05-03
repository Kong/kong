local feature_flags = require "kong.enterprise_edition.feature_flags"


local FLAGS = feature_flags.FLAGS


local overwrite_functions = {
  ["key-auth"] = function(schema)
    if not feature_flags.is_enabled(FLAGS.KEY_AUTH_DISABLE_KEY_IN_BODY) then
      return true
    end

    ngx.log(ngx.DEBUG, "key-auth key_in_body feature disabled")
    schema.fields["key_in_body"].default = nil
    schema.fields["key_in_body"].overwrite = false
    return true
  end,
  ["hmac-auth"] = function(schema)
    if not feature_flags.is_enabled(FLAGS.HMAC_AUTH_DISABLE_VALIDATE_REQUEST_BODY) then
      return true
    end

    ngx.log(ngx.DEBUG, "hmac-auth validate_request_body feature disabled")
    schema.fields["validate_request_body"].default = nil
    schema.fields["validate_request_body"].overwrite = false
    return true
  end,
}


local function add_overwrite(plugin_name, schema)
  if not plugin_name or not schema then
    return true
  end

  if not overwrite_functions[plugin_name] then
    return true
  end

  return overwrite_functions[plugin_name](schema)
end


return {
  add_overwrite = add_overwrite,
}

