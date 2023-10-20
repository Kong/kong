-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local pgmoon = require("pgmoon")

local function get_db_params()
  local host, port, db, user, password
  if #args < 2 then
    print(
      "Running in interactive mode. If you wish to specify at the CLI please use the following positional arguments\nUsage: pg.lua <host> <port> <db> <user> <password>\n")
    io.write("Enter your DB host: ")
    io.flush()
    host = io.read()

    io.write("Enter your DB port: ")
    io.flush()
    port = tonumber(io.read())

    io.write("Enter your DB name: ")
    io.flush()
    db = io.read()

    io.write("Enter your DB user: ")
    io.flush()
    user = io.read()

    io.write("Enter your DB password: ")
    io.flush()
    os.execute("stty -echo")
    password = io.read()
    os.execute("stty echo")
  else
    host = args[2]
    port = tonumber(args[3])
    db = args[4]
    user = args[5]
    password = args[6]
  end

  return host, port, db, user, password
end

local function connect(host, port, db, user, password)
  local interval = 1
  local header =
    "\n+----------------------------------------------------------------------------------------+\n| Table                                              | Size            | Relation Size   |\n+----------------------------------------------------------------------------------------+"
  local footer =
    "+----------------------------------------------------------------------------------------+"
  local size_query =
    [[ select table_name, pg_size_pretty(pg_relation_size(quote_ident(table_name))),
                        pg_relation_size(quote_ident(table_name)) from information_schema.tables
                        where table_schema = 'public' order by 3 desc ]]

  local slow_query =
    [[ SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
                        FROM pg_stat_activity
                        WHERE
                        (now() - pg_stat_activity.query_start) > interval ']] ..
      interval .. [[" seconds'  order BY duration DESC  ]]

  local active_connections =
    [[ SELECT pid, datname, usename, application_name, client_hostname
                                ,client_port, backend_start, query_start, query, state FROM pg_stat_activity
                               WHERE state = 'active' ]]

  local entities = {
    "routes", "services", "consumers", "plugins", "upstreams", "targets",
    "workspaces"
  }

  local pg = pgmoon.new({
    host = host,
    port = port,
    database = db,
    user = user,
    password = password
  })

  local ok, err = pg:connect()

  if not ok then
    print("Connection to Postgres failed Reason: " .. err)
    os.exit(1)
  end

  -- DB sizes
  local res, err = pg:query(size_query)
  if not res then
    print("Unable to query database " .. err)
  else
    print("DB connectivity:\n")
    print(header)
    for _, row in ipairs(res) do
      print(string.format("| %-50s | %-15s | %-15s |", row.table_name,
                          row.pg_size_pretty, row.pg_relation_size))
    end
    print(footer)
  end

  local res, _ = pg:query(slow_query)
  if not res then
    print("Unable to query database")
  else
    if #res > 0 then
      print("\n=============== Slow Queries ===============\n ")
      for _, row in ipairs(res) do
        print(string.format(
                "PID: %s \nDuration: %s \nQuery: %s \n-------------", row.pid,
                row.duration, row.query))
      end
      print("+-----------------------------------+\n")
    end
  end

  print("\n=============== Entity Counts ===============\n ")
  local header =
    "+-----------------------------------+\n| Entity          | Count           |\n+-----------------------------------+"
  print(header)
  for _, val in ipairs(entities) do
    local res, _ = pg:query("SELECT COUNT(*) FROM " .. val)
    if not res then
      print("Unable to query database")
    else
      print(string.format("| %-15s | %-15s |", val, res[1].count))
    end
  end
  print("+-----------------------------------+\n")

  print("\n=============== Active Connections ===============\n ")
  local res, _ = pg:query(active_connections)
  if not res then
    print("Unable to query database")
  else
    for _, row in ipairs(res) do
      print(string.format(
              "PID: %s \nusename: %s \nApplication Name: %s \nClient Host: %s \nQuery %s \n",
              row.pid, row.usename, row.application_name, row.client_host,
              row.query))
    end
  end
  print("+-----------------------------------+\n")

  pg:keepalive()
end

local host, port, db, user, password = get_db_params()
connect(host, port, db, user, password)

