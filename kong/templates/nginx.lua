-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return [[
pid pids/nginx.pid;
error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

# injected nginx_main_* directives
> for _, el in ipairs(nginx_main_directives) do
$(el.name) $(el.value);
> end

env KONG_LICENSE_DATA;
env KONG_LICENSE_PATH;

events {
    # injected nginx_events_* directives
> for _, el in ipairs(nginx_events_directives) do
    $(el.name) $(el.value);
> end
}

> if role == "control_plane" or #proxy_listeners > 0 or #admin_listeners > 0 or #status_listeners > 0 then
http {
    include 'nginx-kong.conf';
}
> end

> if #stream_listeners > 0 then
stream {
    include 'nginx-kong-stream.conf';
}
> end
]]
