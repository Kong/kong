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
