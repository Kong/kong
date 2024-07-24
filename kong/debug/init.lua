-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lapis       = require "lapis"
local api_helpers = require "kong.api.api_helpers"

local ngx = ngx


local app = lapis.Application()


app.default_route = api_helpers.default_route
app.handle_404 = api_helpers.handle_404
app.handle_error = api_helpers.handle_error
app:before_filter(api_helpers.before_filter)

ngx.log(ngx.DEBUG, "Loading Debug API endpoints")

-- Load debug routes
api_helpers.attach_routes(app, require "kong.api.routes.debug")
-- Load status routes
api_helpers.attach_routes(app, require "kong.api.routes.health")


return app
