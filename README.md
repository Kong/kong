# KONG: The API Management Layer

[![Build Status][travis-badge]][travis-url] [![Build Status][license-badge]][license-url] 

- Website: [getkong.org](http://getkong.org/)
- Docs: [getkong.org/docs](http://getkong.org/docs)
- Mailing List: [Google Groups](https://groups.google.com/forum/#!forum/konglayer)
- Gitter Chat: [mashape/kong](https://gitter.im/Mashape/kong)

**Kong is next-generation software for securing, managing and extending APIs & Microservices**. If you're building for web, mobile or IoT you will likely end up needing to implement common functionality on top of your actual software. Kong can help by acting as a gateway for any HTTP resource while providing logging, authentication and other functionality through plugins. 

Powered by NGINX and Cassandra with a focus on high performance and reliability, Kong runs in production at [Mashape](https://www.mashape.com) where it has handled billions of API requests for over ten thousand APIs.

[![](http://i.imgur.com/fxkvt5k.png)](http://getkong.org/)

## Core Features

- **CLI**: Control your Kong cluster from the command line just like Neo in the matrix.
- **REST API**: Kong can be operated with it's RESTful API for maximum flexibility.
- **Scalability**: Distributed by nature, Kong scales horizontally simply by adding nodes.
- **Performance**: Kong handles load with ease by scaling and using nginx at the core.
- **Plugins**: Extendable architecture for adding functionality to kong and APIs.
  - **Logging**: Log requests and responses to your system over TCP, UDP or to disk.
  - **Monitoring**: Live monitoring provides key load and performance server metrics
  - **Authentication**: Manage consumer credentials query sring and header tokens.
  - **Rate-limiting**: Block and throttle requests based on IP or authentication.
  - **Transformations**: Add, remove or manipulate HTTP params and headers on-the-fly. 
  - **CORS**: Enable cross origin requests to your APIs that would otherwise be blocked.
  - **Anything**:Need custom functionality? Extend Kong with your own Lua plugins!

## Documentation 

Full versioned documentation is available at [GetKong.org](http://getkong.org):

- [Installation](http://www.getkong.org/download)
- [Quick Start](http://getkong.org/docs/latest/getting-started/quickstart/)
- [CLI Reference](http://getkong.org/docs/latest/cli/)
- [API Reference](http://getkong.org/docs/latest/admin-api)
- [Configuration](http://getkong.org/docs/latest/configuration/)

## Development

Please see the [CONTRIBUTING.md][kong-contrib] if you would like to have your changes merged into Kong.

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

#### Makefile Operations

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

## License

Kong is provided under the [MIT License][license-url]. 

[kong-contrib]: https://github.com/Mashape/kong/blob/master/CONTRIBUTING.md
[kong-changelog]: https://github.com/Mashape/kong/blob/master/CHANGELOG.md

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat

[license-url]: https://github.com/Mashape/kong/blob/master/LICENSE
[license-badge]: https://img.shields.io/github/license/mashape/kong.svg
