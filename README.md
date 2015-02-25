# Kong

[![Build Status][travis-image]][travis-url] [![Gitter][gitter-image]][gitter-url]

Kong is a scalable and customizable API Management Layer built on top of nginx.

Documentation can be found at: [getkong.org/docs](http://getkong.org/docs)

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
bin/kong -c config.dev/kong.yml -n config.dev/nginx.conf start
```

#### Makefile

When developing, use the `Makefile` for doing the following operations:

| Name         | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `install`    | Install the Kong luarock globally                                                                   |
| `dev`        | Setup your development enviroment (creates `config.dev` and `config.tests` configurations)          |
| `clean`      | Clean the development environment                                                                   |
| `migrate`    | Migrate your database schema according to the development Kong config inside `config.dev`           |
| `reset`      | Reset your database schema according to the development Kong config inside `config.dev`             |
| `seed`       | Seed your database according to the development Kong config inside `config.dev`                     |
| `drop`       | Drop your database according to the development Kong config inside `config.dev`                     |
| `test`       | Run the unit tests                                                                                  |
| `test-proxy` | Run the proxy integration tests                                                                     |
| `test-web`   | Run the web integration tests                                                                       |
| `test-all`   | Run all unit + integration tests at once                                                            |

#### Scripts

Those scripts provide handy features while developing Kong:

##### db.lua

```bash
# Complete usage
scripts/db.lua --help

# Migrate up
scripts/db.lua migrate [configuration_path] # for all commands, the default configuration_path is config.dev/kong.yml

# Migrate down (currently equivalent to reset)
scripts/db.lua rollback

# Reset DB (danger!)
scripts/db.lua reset

# Seed DB
scripts/db.lua seed

# Drop DB (danger!)
scripts/db.lua drop
```

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-image]: https://img.shields.io/travis/Mashape/kong.svg?style=flat
[gitter-url]: https://gitter.im/Mashape/kong?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
[gitter-image]: https://badges.gitter.im/Join%20Chat.svg
[lua-install-url]: http://www.lua.org/download.html
[luarocks-url]: https://luarocks.org
[pcre-url]: http://www.pcre.org/
[openssl-url]: https://www.openssl.org/
[cassandra-url]: http://cassandra.apache.org/
