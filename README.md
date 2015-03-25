# KONG - The API Layer

[![Build Status][travis-badge]][travis-url]
[![Coverage Status][coveralls-badge]][coveralls-url]
[![Gitter][gitter-badge]][gitter-url]

Kong is a scalable and customizable API Management Layer built on top of Nginx.

* **[Installation](#installation)**
* **[Documentation](#documentation)**
* **[Usage](#usage)**
* **[Development](#development)**

## Installation

See [INSTALL.md](INSTALL.md) for installation instructions on your platform.

## Usage

Use Kong through the `kong` executable. If you installed Kong via luarocks, then `kong` should be in your `$PATH`.

```bash
$ kong --help
```

## Getting started

Kong will look by default for a configuration file at `/etc/kong/kong.yml`. Make sure to copy the provided `kong.yml` there and edit it to let Kong access your Cassandra cluster.

Let's start Kong:

```bash
$ kong start
```

This should have run the migrations to prepare your Cassandra keyspace, and you should see a success message if Kong has started.

Kong listens on these ports:
- `:8000`: requests proxying
- `:8001`: Kong's configuration API by which you can add APIs and accounts

#### Hello World: Proxying your first API

Let's add [mockbin](http://mockbin.com/) as an API:

```bash
$ curl -i -X POST \
  --url http://localhost:8001/apis/ \
  --data 'name=mockbin&target_url=http://mockbin.com/&public_dns=mockbin.com'
HTTP/1.1 201 Created
...
```

And query it through Kong:

```bash
$ curl -i -X GET \
  --url http://localhost:8000/ \
  --header 'Host: mockbin.com'
HTTP/1.1 200 OK
...
```

#### Accounts and plugins

One of Kong's core principle is its extensibility through [plugins](http://getkong.org/plugins/), which allow you to add features to your APIs.

Let's configure the **headerauth** plugin to add authentication to your API. Make sure it is in the `plugins_available` property of your configuration.

```bash
# Make sure the api_id parameter matches the one of mockbin created earlier
$ curl -i -X POST \
  --url http://localhost:8001/plugins/ \
  --data 'name=headerauth&api_id=<api_id>&value.header_names=apikey'
HTTP/1.1 201 Created
...
```

If we make the same request again:

```bash
$ curl -i -X GET \
  --url http://localhost:8000/ \
  --header 'Host: mockbin.com'
HTTP/1.1 403 Forbidden
...
{"message":"Your authentication credentials are invalid"}
```

To authenticate against your API, you now need to create an account associated with an application. An application links an account and an API.

```bash
$ curl -i -X POST \ 
  --url http://localhost:8001/accounts/
  --data ''
HTTP/1.1 201 Created
...

# Make sure the given account_id matches the freshly created account
$ curl -i -X POST \
  --url http://localhost:8001/applications/
  --data 'public_key=123456&account_id=<account_id>'
HTTP/1.1 201 Created
...
```

That application (which has "123456" as an API key) can now consume authenticated APIs such as the previously configured mockbin:

```bash
$ curl -i -X GET \
  --url http://localhost:8000/ \
  --header 'Host: mockbin.com' \
  --header 'apikey: 123456'
HTTP/1.1 200 OK
...
```

To go further into mastering Kong, refer to the complete [documentation](#documentation).

## Documentation

A complete documentation on how to configure and use Kong can be found at: [getkong.org/docs](http://getkong.org/docs). **(coming soon)**

## Development

To develop for Kong, simply run `[sudo] make install` in a clone of this repo. Then run:

```bash
$ make dev
```

This will install development dependencies and create your environment configuration files (`kong_TESTS.yml` and `kong_DEVELOPMENT.yml`).

- Run the tests:

```bash
$ make test-all
```

- Run Kong with the development configuration:

```bash
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
