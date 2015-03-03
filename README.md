# Kong

[![Build Status][travis-badge]][travis-url] [![Coverage Status][coveralls-badge]][coveralls-url] [![Gitter][gitter-badge]][gitter-url]

Kong is a scalable and customizable API Management Layer built on top of nginx.

* **[Installation](#installation)**
* **[Documentation](#documentation)**
* **[Usage](#usage)**
* **[Development](#development)**

## Installation

See [INSTALL.md](INSTALL.md) for installation instructions on your platform.

## Documentation

A complete documentation can be found at: [getkong.org/docs](http://getkong.org/docs)

## Usage

Use Kong through the `bin/kong` executable. Make sure your Cassandra instance is running.

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

This will install development dependencies and create your environment configuration files (`dev` and `tests`). Setup your database access for each of these enviroments (be careful about keyspaces, since Kong already uses `kong` and unit tests already use `kong_tests`).

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
| `dev`        | Setup your development enviroment (install dev deps and creates `config.dev` and `config.tests`)    |
| `clean`      | Clean the development environment                                                                   |
| `migrate`    | Migrate your database schema according to the development Kong config inside `config.dev`           |
| `reset`      | Reset your database schema according to the development Kong config inside `config.dev`             |
| `seed`       | Seed your database according to the development Kong config inside `config.dev`                     |
| `drop`       | Drop your database according to the development Kong config inside `config.dev`                     |
| `lint`       | Lint Lua in `src/`                                                                                  |
| `coverage`   | Run unit tests + coverage report (only unit-tested modules)                                         |
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

# Revert latest migration
scripts/db.lua rollback

# Revert all migrations (danger! this will delete your data)
scripts/db.lua reset

# Seed DB (danger! this will delete your data)
scripts/db.lua seed

# Drop DB (danger! this will delete your data)
scripts/db.lua drop
```

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat
[coveralls-url]: https://coveralls.io/r/Mashape/kong?branch=master
[coveralls-badge]: https://coveralls.io/repos/Mashape/kong/badge.svg?branch=master
[gitter-url]: https://gitter.im/Mashape/kong?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
[gitter-badge]: https://badges.gitter.im/Join%20Chat.svg
