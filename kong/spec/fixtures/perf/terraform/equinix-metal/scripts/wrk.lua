-- luacheck: ignore
--This script is executed in conjuction with the wrk benchmarking tool via demo.sh
math.randomseed(os.time()) -- Generate PRNG seed
local rand = math.random -- Cache random method

-- Get env vars for consumer and api count or assign defaults
local consumer_count = os.getenv("KONG_DEMO_CONSUMER_COUNT") or 5
local service_count = os.getenv("KONG_DEMO_SERVICE_COUNT") or 5
local workspace_count = os.getenv("KONG_DEMO_WORKSPACE_COUNT") or 1
local route_per_service = os.getenv("KONG_DEMO_ROUTE_PER_SERVICE") or 5

function request()
  -- generate random URLs, some of which may yield non-200 response codes
  local random_consumer = rand(consumer_count)
  local random_service = rand(service_count)
  local random_route = rand(route_per_service)
  -- Concat the url parts
  if workspace_count == 1 then
    url_path = string.format("/s%s-r%s?apikey=consumer-%s", random_service, random_route, random_consumer)
  else
    random_workspace = rand(workspace_count)
    url_path = string.format("/w%s-s%s-r%s?apikey=consumer-%s", random_workspace, random_service, random_route, random_consumer)
  end
  -- Return the request object with the current URL path
  return wrk.format(nil, url_path, headers)
end

--[[function done(summary, latency, requests)
  local file = io.open("output.csv", "a")
  file:write(string.format(
    "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
    os.time(),
    latency.min,
    latency.max,
    latency.mean,
    latency:percentile(50),
    latency:percentile(90),
    latency:percentile(99),
    summary.duration,
    summary.requests,
    summary.errors.connect,
    summary.errors.read,
    summary.errors.write,
    summary.errors.status,
    summary.errors.timeout
  ))
end]]
