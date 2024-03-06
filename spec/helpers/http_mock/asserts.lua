local setmetatable = setmetatable
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local error = error

local http_mock = {}

local build_in_checks = {}

local eventually_MT = {}
eventually_MT.__index = eventually_MT

local step_time = 0.01

-- example for a check function
-- local function(session, status)
--   -- must throw error if the assertion is not true
--   -- instead of return false
--   assert.same(session.resp.status, status)
--   -- return a string to tell what condition is satisfied
--   -- so we can construct an error message for reverse assertion
--   -- in this case it would be "we don't expect that: has a response with status 200"
--   return "has a response with status " .. status
-- end

local function eventually_has(check, mock, ...)
  local time = 0
  local ok, err
  while time < mock.eventually_timeout do
    local logs = mock:retrieve_mocking_logs()
    for _, log in ipairs(logs) do
    -- use pcall so the user may use lua assert like assert.same
      ok, err = pcall(check, log, ...)
      if ok then
        return true
      end
    end

    ngx.sleep(step_time)
    time = time + step_time
  end

  error(err or "assertion fail. No request is sent and recorded.", 2)
end

-- wait until timeout to check if the assertion is true for all logs
local function eventually_all(check, mock, ...)
  local time = 0
  local ok, err
  while time < mock.eventually_timeout do
    local logs = mock:retrieve_mocking_logs()
    for _, log in ipairs(logs) do
      ok, err = pcall(check, log, ...)
      if not ok then
        error(err or "assertion fail", 2)
      end
    end

    ngx.sleep(step_time)
    time = time + step_time
  end

  return true
end

-- a session is a request/response pair
function build_in_checks.session_satisfy(session, f)
  return f(session) or "session satisfy"
end

function build_in_checks.request_satisfy(session, f)
  return f(session.req) or "request satisfy"
end

function build_in_checks.request()
  return "request exist"
end

function build_in_checks.response_satisfy(session, f)
  return f(session.resp) or "response satisfy"
end

function build_in_checks.error_satisfy(session, f)
  return f(session.err) or "error satisfy"
end

function build_in_checks.error(session)
  assert(session.err, "has no error")
  return "has error"
end

local function register_assert(name, impl)
  eventually_MT["has_" .. name] = function(self, ...)
    return eventually_has(impl, self.__mock, ...)
  end

  eventually_MT["all_" .. name] = function(self, ...)
    return eventually_all(impl, self.__mock, ...)
  end

  local function reverse_impl(session, ...)
    local ok, err = pcall(impl, session, ...)
    if ok then
      error("we don't expect that: " .. (name or err), 2)
    end
    return true
  end

  eventually_MT["has_no_" .. name] = function(self, ...)
    return eventually_all(reverse_impl, self.__mock, ...)
  end

  eventually_MT["not_all_" .. name] = function(self, ...)
    return eventually_has(reverse_impl, self.__mock, ...)
  end

  eventually_MT["has_one_without_" .. name] = eventually_MT["not_all_" .. name]
end

for name, impl in pairs(build_in_checks) do
  register_assert(name, impl)
end


function http_mock:_set_eventually_table()
  local eventually = setmetatable({}, eventually_MT)
  eventually.__mock = self
  self.eventually = eventually
  return eventually
end

-- usually this function is not called by a user. I will add more assertions in the future with it. @StarlightIbuki

-- @function http_mock.register_assert()
-- @param name: the name of the assertion
-- @param impl: the implementation of the assertion
-- implement a new eventually assertion
-- @usage:
-- impl is a function
-- -- @param session: the session object, with req, resp, err, start_time, end_time as fields
-- -- @param ...: the arguments passed to the assertion
-- -- @return: human readable message if the assertion is true, or throw error if not
--
-- a session means a request/response pair.
-- The impl callback throws error if the assertion is not true
-- and returns a string to tell what condition is satisfied
-- This design is to allow the user to use lua asserts in the callback
-- (or even callback the registered assertion accept as argument), like the example;
-- and for has_no/not_all assertions, we can construct an error message for it like:
-- "we don't expect that: has header foo"
-- @example:
-- http_mock.register_assert("req_has_header", function(mock, name)
--   assert.same(name, session.req.headers[name])
--   return "has header " .. name
-- end)
-- mock.eventually:has_req_has_header("foo")
-- mock.eventually:has_no_req_has_header("bar")
-- mock.eventually:all_req_has_header("baz")
-- mock.eventually:not_all_req_has_header("bar")
http_mock.register_assert = register_assert

return http_mock
