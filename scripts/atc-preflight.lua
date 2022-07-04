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

local function get_services(uri)
  print("Querying kong services ...")

  local uri = uri .. "/services"
  local list = {}

  while true do
    local res, err = httpc:request_uri(uri)
    if not res then
      print("Get service failed: ", err)
      return
    end

    if res.status ~= 200 then
      print("Get service failed: ", res.body)
      return
    end

    local json = cjson_decode(res.body)

    for _, v in ipairs(json.data) do
      tb_insert(list, v.name)   -- v.id
    end

    if json.next == null then
      break

    else
      uri = json.next
    end

  end -- while

  print("Done. Services count is: ", #list)

  return list
end

local function get_routes(uri, svc)
  print("Querying routes of [ ", svc, " ] ...")

  local list = {}

  local uri = uri .. "/services/" .. svc .. "/routes"

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

    for _, v in ipairs(json.data) do
      tb_insert(list, v)
    end

    if json.next == null then
      break

    else
      uri = json.next
    end
  end -- while

  print("Done. Routes count is: ", #list)

  return list
end

local function validate_routes(list)
  local ok = 0
  local fail = 0

  local fail_routes = {}
  local reg = [[(.*?):\d+]]

  for _, r in ipairs(list) do

    -- atc only support http/https
    -- if protocol is tcp/grpc, fallback to traditional
    for _, p in ipairs(r.protocols) do
      if p:sub(1, 4) ~= "http" then
        ok = ok + 1
        goto continue
      end
    end

    if r.hosts then

      if #r.hosts <= 1 then
        ok = ok + 1
        goto continue
      end

      -- now atc can't deal with "host || host:port"
      for _, h in ipairs(r.hosts) do
        local m = re_match(h, reg, "jo")

        if m then
          for _, x in ipairs(r.hosts) do
            if x == m[1] then
              fail = fail + 1
              tb_insert(fail_routes, r.id)

              goto continue
            end
          end -- for
        end -- if m
      end -- for

    end

    ok = ok + 1

    ::continue::
  end -- for list

  return ok, fail, fail_routes
end

local function preflight()
  local uri = arg[1]

  if not uri then
    help()
    return
  end

  print("URI is [ ", uri, " ]\n")

  local svc_list = get_services(uri)

  print("\nNow begin to check routes.\n")

  for _, s in ipairs(svc_list) do
    local routes = get_routes(uri, s)

    local ok, fail, fail_routes = validate_routes(routes)

    print("ok = ", ok, ", fail = ", fail)

    if fail > 0 then
      print("uncompatible routes are:")
      for _, id in ipairs(fail_routes) do
        print("  ", id)
      end
    end

    print()
  end
end

--- main workflow ---
preflight()

