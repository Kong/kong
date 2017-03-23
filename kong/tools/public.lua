local pcall = pcall
local ngx_log = ngx.log
local ERR = ngx.ERR


local _M = {}


do
  local ngx_req_get_post_args = ngx.req.get_post_args

  function _M.get_post_args()
    local ok, res, err = pcall(ngx_req_get_post_args)

    if not ok or err then
      local msg = res and res or err
      ngx_log(ERR, "could not get body args: ", msg)
      return {} -- TODO return an immutable table here
    end

    return res
  end
end


return _M
