# KONG: The API Management Layer

[![Build Status][travis-badge]][travis-url] [![Build Status][license-badge]][license-url] 

- Website: [getkong.org](http://getkong.org)
- Mailing list: [Google Groups](https://groups.google.com/forum/#!forum/konglayer)
- IRC: `#kong` on Freenode
- gitter: [mashape/kong](https://gitter.im/Mashape/kong)

## Documentation 

Complete & versioned [documentation](http://www.getkong.org/docs) is available on the Kong website. 

## Features

Kong secures, manages & extends HTTP APIs or Microservices. Powered by NGINX and Cassandra with a focus on high performance and reliability, Kong runs in production at [Mashape](https://www.mashape.com) where it has handled billions of API requests for over ten thousand APIs.

- **CLI**: Control your Kong cluster from the command line like neo in the matrix.
- **REST API**: Kong can be operated with it's RESTful API for maximum flexibility.
- **Plugins**: Use Kong plugins to add functionality on top of APIs and Microservices.
- **Scalable**: Distributed by nature Kong can scale horizontally with adding new nodes.

![](http://i.imgur.com/B1e3QI6.png)

## Development

1. Clone the repository and make it your working directory.
2. Run `[sudo] make install`

  This will build and install the `kong` luarock globally.

3. Run `make dev`

  This will install development dependencies and create your environment configuration files:

  - `kong_TESTS.yml`
  - `kong_DEVELOPMENT.yml`

4. Run the tests:

  ```bash
  make test-all
  ```

5. Run Kong with the development configuration file:

   ```bash
   $ kong start -c kong_DEVELOPMENT.yml
   ```

When developing, use the `Makefile` for doing the following operations:

| Name          | Description                                                              |
| -------------:| -------------------------------------------------------------------------|
| `install`     | Install the Kong luarock globally                                        |
| `dev`         | Setup your development environment                                       |
| `run`         | Run the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)               |
| `seed`        | Seed the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)              |
| `drop`        | Drop the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)              |
| `lint`        | Lint Lua files in `kong/`                                                |
| `coverage`    | Run unit tests + coverage report (only unit-tested modules)              |
| `test`        | Run the unit tests                                                       |
| `test-all`    | Run all unit + integration tests at once                                 |

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat

[license-url]: https://github.com/Mashape/kong/blob/master/LICENSE
[license-badge]: https://img.shields.io/github/license/mashape/kong.svg
