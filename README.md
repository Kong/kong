## Kong

[![Build Status](https://travis-ci.org/Mashape/kong.svg)](https://travis-ci.org/Mashape/kong)

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

### Installing Kong

There are two ways to install Kong.

* Using LuaRocks: `sudo luarocks install kong`
* From source: `sudo make install`

### Running Kong

Execute `kong start`.

To see all the available options, run `kong -h`.

### Running Kong for development

Running Kong for development requires two steps:

* Execute `make dev`.
* Execute `kong -c dev/kong-dev.conf -n dev/nginx-dev.conf`

The `make dev` command will create a git-ignored `dev` folder with both a copy of Kong and the nginx configuration. This will prevent to accidentally push to master development configuration files.

### Makefile for development

When developing, use the `Makefile` for doing the following operations:

#### Makefile

| Name         | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `install`    | Install the Kong luarock globally                                                                   |
| `dev`        | Duplicates the default configuration in a git-ignored `dev` folder                                  |
| `clean`      | Cleans the development environment                                                                  |
| `reset`      | Reset your database schema according to the development Kong config inside the `dev` folder         |
| `seed`       | Seed your database according to the development Kong config inside the `dev` folder                 |
| `drop`       | Drop your database according to the development Kong config inside the `dev` folder                 |
| `test`       | Runs the unit tests                                                                                 |
| `test-proxy` | Runs the proxy integration tests                                                                    |
| `test-web`   | Runs the web integration tests                                                                      |
| `test-all`   | Runs all unit + integration tests at once                                                           |

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
