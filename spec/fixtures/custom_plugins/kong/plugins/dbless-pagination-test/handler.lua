-- The test case 04-client_ipc_spec.lua will load this plugin and check its
-- generated error logs.

local LmdbPaginationTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


local function test()
  local db = kong.db

  assert(db.routes.pagination.max_page_size == 2048)
end


function LmdbPaginationTestHandler:init_worker()
  ngx.timer.at(0, test)
end

function LmdbPaginationTestHandler:access(conf)
  local page_size = tonumber(ngx.var.arg_size)
  local rows, err, _, offset = kong.db.routes:page(page_size)
  ngx.header["X-Rows-Number"] = rows and #rows or err
  ngx.header["X-rows-offset"] = tostring(offset)

  ngx.header["X-Max-Page-Size"] = kong.db.routes.pagination.max_page_size

  ngx.exit(200)
end


return LmdbPaginationTestHandler
