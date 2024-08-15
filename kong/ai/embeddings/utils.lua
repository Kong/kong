-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Build the url and headers (in place modification) based on the auth config
local function build_request(auth_config, url, headers, body)
  if auth_config.header_name and auth_config.header_value then
    headers[auth_config.header_name] = auth_config.header_value
  elseif auth_config.query_param_name and auth_config.query_param_value then
    if auth_config.query_param_location == "header" then
      -- append & if there are already query params
      if string.find(url, "?") then
        url = url .. "&"
      else
        url = url .. "?"
      end
      url = url .. string.format("%s=%s", auth_config.query_param_name, auth_config.query_param_value)
    elseif auth_config.query_param_location == "body" then
      body[auth_config.query_param_name] = auth_config.query_param_value
    else
      error("Unsupported query_param_location " .. (auth_config.query_param_location or "nil"))
    end
  end

  return url, headers, body
end

return {
  build_request = build_request,
}
