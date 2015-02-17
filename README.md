## Kong

[![Build Status](https://magnum.travis-ci.com/Mashape/kong.svg?token=ZqXY1Sn8ga8gv6vUrw3N&branch=master)](https://magnum.travis-ci.com/Mashape/kong)

```
 ______________________________________
< ... I have read the INSTRUCTIONS ... >
 --------------------------------------
       \   ,__,
        \  (oo)____
           (__)    )\
              ||--|| *
```

### Requirements
- Lua `5.1`
- Luarocks for Lua `5.1`
- [OpenResty](http://openresty.com/#Download) `1.7.7.2`

### Run Kong (development)

- `make global`
- `make build`
- `make migrate`
- `make run`
  - Proxy: `http://localhost:8000/`
  - API: `http://localhost:8001/`

### Commands

Commands consist of Kong's scripts and Makefile:

#### Makefile

| Name         | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `global`     | Install the Kong luarock globally                                                                   |
| `build`      | Generates a Kong environment (nginx + Kong configurations) in a given folder (see `DIR`)            |
| `migrate`    | Migrate your database according to the given Kong config (see `KONG_CONF`)                          |
| `reset`      | Reset your database schema according to the given Kong config (see `KONG_CONF`)                     |
| `seed`       | Seed your database according to the given Kong config                                               |
| `drop`       | Drop your database according to the given Kong config                                               |
| `run`        | Runs the given Kong environment in a given folder (see `DIR`)                                       |
| `stop`       | Stops the given Kong environment in a given folder (see `DIR`)                                      |
| `test`       | Runs the unit tests                                                                                 |
| `test-proxy` | Runs the proxy integration tests                                                                    |
| `test-web`   | Runs the web integration tests                                                                      |
| `test-all`   | Runs all unit + integration tests at once                                                           |

#### Makefile variables

| Name                   | Default                   | Commands                  | Description                                                                    |
| ---------------------- | ------------------------- | ------------------------- | ------------------------------------------------------------------------------ |
| `DIR`                  | `tmp/`                    | `build|run|stop`          | Specify a folder where an Kong environment lives or should live if building    |
| `KONG_CONF`            | `tmp/kong.conf`           | `build|migrate|seed|drop` | Points the command to the given Kong configuration file                        |
| `DAEMON`               | `off`                     | `build`                   | Sets the nginx daemon property in the generated `nginx.conf`                   |
| `KONG_PORT`            | `8000`                    | `build`                   | Sets Kong's proxy port in the generated `nginx.conf`                           |
| `KONG_WEB_PORT`        | `8001`                    | `build`                   | Sets Kong's web port in the generated `nginx.conf`                             |
| `LUA_CODE_CACHE`       | `off`                     | `build`                   | Sets the nginx `lua_code_cache` property in the generated `nginx.conf`         |
| `LUA_LIB`              | `$(PWD)/src/?.lua;;`      | `build`                   | Sets the nginx `lua_package_path` property in the generated `nginx.conf`       |

#### Scripts

| Name       | Commands                 | Description                                                           | Arguments                                                   |
| ---------- | ------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------- |
| `migrate`  |                          |                                                                       |                                                             |
|            | `create --conf=[conf]`   | Create a migration file for all available databases in the given conf | `--name=[name]` Name of the migration                       |
|            | `migrate --conf=[conf]`  | Migrate the database set in the given conf                            |                                                             |
|            | `rollback --conf=[conf]` | Rollback to the latest executed migration (TODO)                      |                                                             |
|            | `reset --conf=[conf]`    | Rollback all migrations                                               |                                                             |
| `seed`     |                          |                                                                       |                                                             |
|            | `seed --conf=[conf]`     | Seed the database configured in the given conf                        | `-s` (Optional) No output                                   |
|            |                          |                                                                       | `-r` (Optional) Also populate random data (1000 by default) |
|            | `drop --conf=[conf]`     | Drop the database configured in the given conf                        | `-s` (Optional) No output                                   |
