# KONG - The API Layer

[![Build Status][travis-badge]][travis-url]
[![Coverage Status][coveralls-badge]][coveralls-url]
[![Gitter][gitter-badge]][gitter-url]

Kong is a scalable and customizable API Management Layer built on top of Nginx.

> **Note**: getkong.org is still a work in progress, in the meanwhile, please follow instructions in this README instead.

* **[Installation](#installation)**
* **[Documentation](#documentation)**
* **[Usage](#usage)**
* **[Development](#development)**

## Installation

Follow instructions at [getkong.org/download](http://getkong.org/download) for a production installation. **(coming soon)**

See [INSTALL.md](INSTALL.md) for installation instructions on your platform.

## Documentation

A complete documentation on how to configure and use Kong can be found at: [getkong.org/docs](http://getkong.org/docs). **(coming soon)**

## Usage

Use Kong through the `kong` executable. If you installed Kong via luarocks (as previously instructed) then `kong` should be in your `$PATH`.
```
$ kong --help
```

To start Kong (make sure your Cassandra instance is running):

```
$ kong start
```

## Development

To develop for Kong, simply run `[sudo] make install` in a clone of this repo. Then run:

```
$ make dev
```

This will install development dependencies and create your environment configuration files (`kong_TESTS.yml` and `kong_DEVELOPMENT.yml`).

- Run the tests:

```
$ make test-all
```

- Run Kong with the development configuration:

```
$ kong start -c kong_DEVELOPMENT.yml
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

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat
[coveralls-url]: https://coveralls.io/r/Mashape/kong?branch=master
[coveralls-badge]: https://coveralls.io/repos/Mashape/kong/badge.svg?branch=master
[gitter-url]: https://gitter.im/Mashape/kong?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
[gitter-badge]: https://badges.gitter.im/Join%20Chat.svg
