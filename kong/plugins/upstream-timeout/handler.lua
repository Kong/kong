
local UpstreamTimeout = {}


-- TODO: Integration test...
-- Config in-memory cache
-- Should be able to apply on consumer, route, or service

-- Custom errors?
function UpstreamTimeout:access(conf)
    -- TODO: Cache config
    if not conf then end

    -- Needs option to revert to old timeout
    if conf.read_timeout then
        ngx.ctx.balancer_data.read_timeout = conf.read_timeout
    end
    if conf.write_timeout then
        ngx.ctx.balancer_data.send_timeout = conf.write_timeout
    end
    if conf.connect_timeout then
        ngx.ctx.balancer_data.connect_timeout = conf.connect_timeout
    end

end


return UpstreamTimeout
