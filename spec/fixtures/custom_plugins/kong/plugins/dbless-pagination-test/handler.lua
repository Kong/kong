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


return LmdbPaginationTestHandler
