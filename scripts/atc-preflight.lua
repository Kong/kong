#!/usr/bin/env resty

local cjson = require("cjson.safe")
local http = require("resty.http")

local print = print
local ipairs = ipairs
local tb_insert = table.insert
local cjson_decode = cjson.decode
local null = ngx.null
local re_match = ngx.re.match

local httpc = assert(http.new())

local function help()
  print("Usage:\n\n", arg[0], " admin_uri\n")
  print("Example:\n\n", arg[0], " http://localhost:8001\n")
end

-- atc only support http/https
-- if protocol is tcp/grpc, fallback to traditional
local function needs_futher_check(r)
  local flag = true

  for _, p in ipairs(r.protocols) do
    if p:sub(1, 4) ~= "http" then
      flag = false
    end
  end

  if not r.hosts or #r.hosts == 0 then
    flag = false
  end

  return flag
end

local function get_routes(uri)
  print("Querying routes ...")

  local count = 0
  local list = {}

  local uri = uri .. "/routes"

  while true do
    local res, err = httpc:request_uri(uri)
    if not res then
      print("Get routes failed: ", err)
      return
    end

    if res.status ~= 200 then
      print("Get routes failed: ", res.body)
      return
    end

    local json = cjson_decode(res.body)

    for _, r in ipairs(json.data) do
      count = count + 1

      if needs_futher_check(r) then
        tb_insert(list, r)
      end
    end

    if json.next == null then
      break

    else
      uri = json.next
    end
  end -- while

  print("Done. Routes count is: ", count, "\n")

  return list
end

local function contains(set, value)
  for _, v in ipairs(set) do
    if v == value then
      return true
    end
  end

  return false
end

local function validate_routes(list)
  local count = 0
  local fail = 0

  local fail_routes = {}
  local reg = [[(.*?):\d+]]

  for _, r in ipairs(list) do

    -- now atc can't deal well with "host / host:port"
    for _, h in ipairs(r.hosts) do
      local m = re_match(h, reg, "jo")

      if m then
        -- check if hosts have conflict
        for _, x in ipairs(list) do
          if x.id ~= r.id and contains(x.hosts, m[1]) then
            fail = fail + 1
            tb_insert(fail_routes, r.id)

            goto continue
          end
        end -- for

      end -- if m

    end -- for r.hosts

    ::continue::

    if count % 200 == 0 then
      print("Validating routes ...")
    end
    count = count + 1
  end -- for list

  return fail, fail_routes
end

local function preflight()
  local uri = arg[1]

  if not uri then
    help()
    return
  end

  print("URI is [ ", uri, " ]\n")

  print("Now begin to check routes.\n")

  local routes = get_routes(uri)

  local fail, fail_routes = validate_routes(routes)

  print("fail = ", fail)

  if fail > 0 then
    print("uncompatible routes are:")
    for _, id in ipairs(fail_routes) do
      print("  ", id)
    end
  end

  print()
end

--- main workflow ---
preflight()

