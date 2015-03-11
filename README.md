# KONG - The API layer

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

This will install development dependencies and create your environment configuration files (`kong_TESTS.yml` and `kong_DEVELOPMENT.yml`).

- Run the tests:

```
make test-all
```

- Run it:

```
bin/kong -c kong.yml start
```

#### Makefile

When developing, use the `Makefile` for doing the following operations:

| Name          | Description                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------- |
| `install`     | Install the Kong luarock globally                                                                   |
| `dev`         | Setup your development environment                                                                  |
| `run`         | Run the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)                                          |
| `seed`        | Seed the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)                                         |
| `drop`        | Drop the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)                                         |
| `lint`        | Lint Lua files in `src/`                                                                            |
| `coverage`    | Run unit tests + coverage report (only unit-tested modules)                                         |
| `test`        | Run the unit tests                                                                                  |
| `test-proxy`  | Run the proxy integration tests                                                                     |
| `test-server` | Run the server integration tests                                                                    |
| `test-api`    | Run the api integration tests                                                                       |
| `test-all`    | Run all unit + integration tests at once                                                            |

#### Scripts

Those scripts provide handy features while developing Kong:

##### db.lua

This script handles schema migrations, seeding and dropping of the database.

```bash
# Complete usage
scripts/db.lua --help

# Migrate up
scripts/db.lua [-c configuration_file] migrate # for all commands, the default configuration_file is kong.yml

# Revert latest migration
scripts/db.lua rollback

# Revert all migrations (danger! this will delete your data)
scripts/db.lua reset

# Seed DB (danger! this will delete your data)
scripts/db.lua seed

# Drop DB (danger! this will delete your data)
scripts/db.lua drop
```

##### config.lua

This script handles Kong's configuration files. It is better not to directly use it, as it is mainly used through `bin/kong` and the Makefile.

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat
[coveralls-url]: https://coveralls.io/r/Mashape/kong?branch=master
[coveralls-badge]: https://coveralls.io/repos/Mashape/kong/badge.svg?branch=master
[gitter-url]: https://gitter.im/Mashape/kong?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
[gitter-badge]: https://badges.gitter.im/Join%20Chat.svg
