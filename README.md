[![][kong-logo]][kong-url]

[![Build Status][badge-travis-image]][badge-travis-url]
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/Kong/kong/blob/master/LICENSE)
[![Twitter](https://img.shields.io/twitter/follow/thekonginc.svg?style=social&label=Follow)](https://twitter.com/intent/follow?screen_name=thekonginc)

Kong is a cloud-native, fast, scalable, and distributed Microservice
Abstraction Layer *(also known as an API Gateway or API Middleware)*.
Made available as an open-source project in 2015, its core values are
high performance and extensibility.

Actively maintained, Kong is widely used in production at companies ranging
from startups to Global 5000 as well as government organizations.

[Installation](https://konghq.com/install) |
[Documentation](https://docs.konghq.com) |
[Forum](https://discuss.konghq.com) |
[Blog](https://konghq.com/blog) |
IRC (freenode): [#kong](https://webchat.freenode.net/?channels=kong) |
[Nightly Builds][kong-nightly-master]

## Summary

- [**Why Kong?**](#why-kong)
- [**Features**](#features)
- [**Distributions**](#distributions)
- [**Development**](#development)
- [**Enterprise Support & Demo**](#enterprise-support--demo)
- [**License**](#license)

## Why Kong?

If you are building for the web, mobile, or IoT (Internet of Things) you will
likely end up needing common functionality to run your actual software. Kong
can help by acting as a gateway (or a sidecar) for microservices requests while
providing load balancing, logging, authentication, rate-limiting,
transformations, and more through plugins.

[![][kong-benefits]][kong-url]

## Features

- **Cloud-Native**: Platform agnostic, Kong can run from bare metal to
  Kubernetes.
- **Dynamic Load Balancing**: Load balance traffic across multiple upstream
  services.
- **Hash-based Load Balancing**: Load balance with consistent hashing/sticky
  sessions.
- **Circuit-Breaker**: Intelligent tracking of unhealthy upstream services.
- **Health Checks:** Active and passive monitoring of your upstream services.
- **Service Discovery**: Resolve SRV records in third-party DNS resolvers like
  Consul.
- **Serverless**: Invoke and secure AWS Lambda or OpenWhisk functions directly
  from Kong.
- **WebSockets**: Communicate to your upstream services via WebSockets.
- **gRPC**: Communicate to your gRPC services and observe your traffic with logging
  and observability plugins
- **OAuth2.0**: Easily add OAuth2.0 authentication to your APIs.
- **Logging**: Log requests and responses to your system over HTTP, TCP, UDP,
  or to disk.
- **Security**: ACL, Bot detection, whitelist/blacklist IPs, etc...
- **Syslog**: Logging to System log.
- **SSL**: Setup a Specific SSL Certificate for an underlying service or API.
- **Monitoring**: Live monitoring provides key load and performance server
  metrics.
- **Forward Proxy**: Make Kong connect to intermediary transparent HTTP proxies.
- **Authentications**: HMAC, JWT, Basic, and more.
- **Rate-limiting**: Block and throttle requests based on many variables.
- **Transformations**: Add, remove, or manipulate HTTP requests and responses.
- **Caching**: Cache and serve responses at the proxy layer.
- **CLI**: Control your Kong cluster from the command line.
- **REST API**: Kong can be operated with its RESTful API for maximum
  flexibility.
- **Geo-Replicated**: Configs are always up-to-date across different regions.
- **Failure Detection & Recovery**: Kong is unaffected if one of your Cassandra
  nodes goes down.
- **Clustering**: All Kong nodes auto-join the cluster keeping their config
  updated across nodes.
- **Scalability**: Distributed by nature, Kong scales horizontally by simply
  adding nodes.
- **Performance**: Kong handles load with ease by scaling and using NGINX at
  the core.
- **Plugins**: Extendable architecture for adding functionality to Kong and
  APIs.

For more info about plugins and integrations, you can check out the [Kong
Hub](https://docs.konghq.com/hub/).

## Distributions

Kong comes in many shapes. While this repository contains its core's source
code, other repos are also under active development:

- [Kong Docker](https://github.com/Kong/docker-kong): A Dockerfile for
  running Kong in Docker.
- [Kong Packages](https://github.com/Kong/kong/releases): Pre-built packages
  for Debian, Red Hat, and OS X distributions (shipped with each release).
- [Kong Vagrant](https://github.com/Kong/kong-vagrant): A Vagrantfile for
  provisioning a development-ready environment for Kong.
- [Kong Homebrew](https://github.com/Kong/homebrew-kong): Homebrew Formula
  for Kong.
- [Kong CloudFormation](https://github.com/Kong/kong-dist-cloudformation):
  Kong in a 1-click deployment for AWS EC2.
- [Kong AWS AMI](https://aws.amazon.com/marketplace/pp/B06WP4TNKL): Kong AMI on
  the AWS Marketplace.
- [Kong on Microsoft Azure](https://github.com/Kong/kong-dist-azure): Run Kong
  using Azure Resource Manager.
- [Kong on Heroku](https://github.com/heroku/heroku-kong): Deploy Kong on
  Heroku in one click.
- [Kong and Instaclustr](https://www.instaclustr.com/solutions/managed-cassandra-for-kong/): Let
  Instaclustr manage your Cassandra cluster.
- [Kubernetes Ingress Controller for Kong](https://github.com/Kong/kubernetes-ingress-controller):
  Use Kong for Kubernetes Ingress.
- [Nightly Builds][kong-nightly-master]: Builds of the master branch available
  every morning at about 9AM PST.

## Development

If you are planning on developing on Kong, you'll need a development
installation. The `next` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development
Guide](https://docs.konghq.com/latest/plugin-development/), or browse an
online version of Kong's source code documentation in the [Plugin Development
Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/).

#### Docker

You can use Docker / docker-compose and a mounted volume to develop Kong by
following the instructions on [Kong/kong-build-tools](https://github.com/Kong/kong-build-tools#developing-kong).

#### Vagrant

You can use a Vagrant box running Kong and Postgres that you can find at
[Kong/kong-vagrant](https://github.com/Kong/kong-vagrant).

#### Source Install

Kong mostly is an OpenResty application made of Lua source files, but also
requires some additional third-party dependencies. We recommend installing
those by following the source install instructions at
https://docs.konghq.com/install/source/.

Instead of following the second step (Install Kong), clone this repository
and install the latest Lua sources instead of the currently released ones:

```shell
$ git clone https://github.com/Kong/kong
$ cd kong/

# you might want to switch to the development branch. See CONTRIBUTING.md
$ git checkout next

# install the Lua sources
$ luarocks make
```

#### Running for development

Check out the [development section](https://github.com/Kong/kong/blob/next/kong.conf.default#L244)
of the default configuration file for properties to tweak in order to ease
the development process for Kong.

Modifying the [`lua_package_path`](https://github.com/openresty/lua-nginx-module#lua_package_path)
and [`lua_package_cpath`](https://github.com/openresty/lua-nginx-module#lua_package_cpath)
directives will allow Kong to find your custom plugin's source code wherever it
might be in your system.

#### Tests

Install the development dependencies ([busted], [luacheck]) with:

```shell
$ make dev
```

Kong relies on three test suites using the [busted] testing library:

* Unit tests
* Integration tests, which require Postgres and Cassandra to be up and running
* Plugins tests, which require Postgres to be running

The first can simply be run after installing busted and running:

```
$ make test
```

However, the integration and plugins tests will spawn a Kong instance and
perform their tests against it. As so, consult/edit the `spec/kong_tests.conf`
configuration file to make your test instance point to your Postgres/Cassandra
servers, depending on your needs.

You can run the integration tests (assuming **both** Postgres and Cassandra are
running and configured according to `spec/kong_tests.conf`) with:

```
$ make test-integration
```

And the plugins tests with:

```
$ make test-plugins
```

Finally, all suites can be run at once by simply using:

```
$ make test-all
```

Consult the [run_tests.sh](.ci/run_tests.sh) script for a more advanced example
usage of the tests suites and the Makefile.

Finally, a very useful tool in Lua development (as with many other dynamic
languages) is performing static linting of your code. You can use [luacheck]
\(installed with `make dev`\) for this:

```
$ make lint
```

#### Makefile

When developing, you can use the `Makefile` for doing the following operations:

| Name               | Description                                            |
| ------------------:| -------------------------------------------------------|
| `install`          | Install the Kong luarock globally                      |
| `dev`              | Install development dependencies                       |
| `lint`             | Lint Lua files in `kong/` and `spec/`                  |
| `test`             | Run the unit tests suite                               |
| `test-integration` | Run the integration tests suite                        |
| `test-plugins`     | Run the plugins test suite                             |
| `test-all`         | Run all unit + integration + plugins tests at once     |

## Enterprise Support & Demo

If you are working in a large organization you should learn more about [Kong
Enterprise](https://konghq.com/kong-enterprise-edition/).

## License

```
Copyright 2016-2020 Kong Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

[kong-url]: https://konghq.com/
[kong-logo]: https://konghq.com/wp-content/uploads/2018/05/kong-logo-github-readme.png
[kong-benefits]: https://konghq.com/wp-content/uploads/2018/05/kong-benefits-github-readme.png
[kong-nightly-master]: https://bintray.com/kong/kong-nightly/master
[badge-travis-url]: https://travis-ci.org/Kong/kong/branches
[badge-travis-image]: https://travis-ci.org/Kong/kong.svg?branch=master

[busted]: https://github.com/Olivine-Labs/busted
[luacheck]: https://github.com/mpeterv/luacheck
