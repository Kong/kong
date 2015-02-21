# Kong

[![Build Status][travis-image]][travis-url]

Kong is a scalable and customizable API Management Layer built on top of nginx.

* **[Requirements](#requirements)**
* **[Installation](#installation)**
* **[Usage](#usage)**
* **[Development](#development)**

## Requirements
- [Lua][lua-install-url] `5.1`
- [Luarocks][luarocks-url] `2.2.0`
- [OpenResty](http://openresty.com/#Download) `1.7.7.2`
- [pcre-devel][pcre-url]
- [openssl-devel][openssl-url]
- [Cassandra][cassandra-url] `2.1`

## Installation

#### From source

```bash
sudo make install
```

## Usage

Use Kong through the `bin/kong` executable.

The first time ever you're running Kong, you need to make sure to setup Cassandra by executing:

```bash
bin/kong migrate
```

To start Kong:

```bash
bin/kong start
```

See all the available options, with `bin/kong -h`.

## Development

Running Kong for development requires you to run:

```
make dev
```

This will create your environment configuration files (`dev` and `tests`). Setup your database access for each of these enviroments (be careful about keyspaces, since Kong already uses `kong` and unit tests already use `kong_tests`).

- Run the tests:

```
make test-all
```

- Run it:

```
bin/kong -c config.dev/kong.yaml -n config.dev/nginx.conf
```

#### Makefile

When developing, use the `Makefile` for doing the following operations:

| Name         | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `install`    | Install the Kong luarock globally                                                                   |
| `dev`        | Setup your development enviroment (creates `dev` and `tests` configurations)                        |
| `clean`      | Cleans the development environment                                                                  |
| `reset`      | Reset your database schema according to the development Kong config inside the `dev` folder         |
| `seed`       | Seed your database according to the development Kong config inside the `dev` folder                 |
| `drop`       | Drop your database according to the development Kong config inside the `dev` folder                 |
| `test`       | Runs the unit tests                                                                                 |
| `test-proxy` | Runs the proxy integration tests                                                                    |
| `test-web`   | Runs the web integration tests                                                                      |
| `test-all`   | Runs all unit + integration tests at once                                                           |

#### Scripts

Those script provide handy features while developing Kong:

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

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-image]: https://img.shields.io/travis/Mashape/kong.svg?style=flat
[lua-install-url]: http://www.lua.org/download.html
[luarocks-url]: https://luarocks.org
[pcre-url]: http://www.pcre.org/
[openssl-url]: https://www.openssl.org/
[cassandra-url]: http://cassandra.apache.org/
