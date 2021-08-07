-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ERR = ngx.ERR

local function read_request_body(skip_large_bodies)
  ngx.req.read_body()
  local body = ngx.req.get_body_data()

  if not body then
    -- see if body was buffered to tmp file, payload could have exceeded client_body_buffer_size
    local body_filepath = ngx.req.get_body_file()
    if body_filepath then
      if skip_large_bodies then
        ngx.log(ERR, "request body was buffered to disk, too large")
      else
        local file = io.open(body_filepath, "rb")
        body = file:read("*all")
        file:close()
      end
    end
  end

  return body
end


return {
  read_request_body = read_request_body
}
