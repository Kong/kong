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
- [Openrestify](http://openresty.com/#Download) `1.7.4.1`

### Run apenode (development)

- `make global`
- `make build`
- `make migrate`
- `make run`
  - Proxy: `http://localhost:8000/`
  - API: `http://localhost:8001/`

### Commands

Commands consist of apenode's scripts and Makefile:

#### Makefile

| Name         | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `global`     | Install the apenode luarock globally                                                                |
| `build`      | Generates an apenode environment (nginx + apenode configurations) in a given folder (see `ENV_DIR`) |
| `migrate`    | Migrate your database according to the given apenode config (see `ENV_APENODE_CONF`)                |
| `seed`       | Seed your database according to the given apenode config                                            |
| `drop`       | Drop your database according to the given apenode config                                            |
| `run`        | Runs the given apenode environment in a given folder (see `ENV_DIR`)                                |
| `stop`       | Stops the given apenode environment in a given folder (see `ENV_DIR`)                               |
| `test`       | Runs the unit tests                                                                                 |
| `test-proxy` | Runs the proxy integration tests                                                                    |
| `test-web`   | Runs the web integration tests                                                                      |
| `test-all`   | Runs all unit + integration tests at once                                                           |

#### Makefile variables

| Name                   | Default                   | Commands                  | Description                                                                    |
| ---------------------- | ------------------------- | ------------------------- | ------------------------------------------------------------------------------ |
| `ENV_DIR`              | `tmp/`                    | `build|run|stop`          | Specify a folder where an apenode environment lives or should live if building |
| `ENV_APENODE_CONF`     | `tmp/apenode.dev.yaml`    | `build|migrate|seed|drop` | Points the command to the given apenode configuration file                     |
| `ENV_DAEMON`           | `off`                     | `build`                   | Sets the nginx daemon property in the generated `nginx.conf`                   |
| `ENV_APENODE_PORT`     | `8000`                    | `build`                   | Sets the apenode proxy port in the generated `nginx.conf`                      |
| `ENV_APENODE_WEB_PORT` | `8001`                    | `build`                   | Sets the apenode web port in the generated `nginx.conf`                        |
| `ENV_LUA_CODE_CACHE`   | `off`                     | `build`                   | Sets the nginx `lua_code_cache` property in the generated `nginx.conf`         |
| `ENV_LUA_LIB`          | `$(PWD)/src/?.lua;;`      | `build`                   | Sets the nginx `lua_package_path` property in the generated `nginx.conf`       |

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

### API

The Apenode provides APIs to interact with the underlying data model and create APIs, accounts and applications

#### Create APIs

`POST /apis/`

* **required** `public_dns`: The public DNS of the API
* **required** `target_url`: The target URL
* **required** `authentication_type`: The authentication to enable on the API, can be `query`, `header`, `basic`.
* **required** `authentication_key_names`: A *comma-separated* list of authentication parameter names, like `apikey` or `x-mashape-key`.

#### Create Accounts

`POST /accounts/`

* `provider_id`: A custom id to be set in the account entity

#### Create Applications

`POST /applications/`

* **required** `account_id`: The `account_id` that the application belongs to.
* `public_key`: The public key, or username if Basic Authentication is enabled.
* **required** `secret_key`: The secret key, or api key, or password if Basic authentication is enabled. Use only this fields for simple api keys.
