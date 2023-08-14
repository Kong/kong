[![][kong-logo]][kong-url]

## CI status

### Master branch

[![Build & Test](https://github.com/Kong/kong-ee/actions/workflows/build_and_test.yml/badge.svg)](https://github.com/Kong/kong-ee/actions/workflows/build_and_test.yml)
[![Package & Release](https://github.com/Kong/kong-ee/actions/workflows/release.yml/badge.svg)](https://github.com/Kong/kong-ee/actions/workflows/release.yml)

## 2.8 LTS branch

[![Build & Test](https://github.com/Kong/kong-ee/actions/workflows/build_and_test.yml/badge.svg?branch=next%2F2.8.x.x)](https://github.com/Kong/kong-ee/actions/workflows/build_and_test.yml)
[![Package & Release](https://github.com/Kong/kong-ee/actions/workflows/release.yml/badge.svg?branch=next%2F2.8.x.x)](https://github.com/Kong/kong-ee/actions/workflows/release.yml)


Kong is a cloud-native, fast, scalable, and distributed Microservice
Abstraction Layer *(also known as an API Gateway or API Middleware)*.
Made available as an open-source project in 2015, its core values are
high performance and extensibility.

Actively maintained, Kong is widely used in production at companies ranging
from startups to Global 5000 as well as government organizations.

[Installation](https://docs.konghq.com/enterprise/latest/deployment/installation/overview/) |
[Documentation](https://docs.konghq.com/enterprise) |
[Forum](https://discuss.konghq.com) |
[Blog](https://konghq.com/blog) |
IRC (freenode): [#kong](https://webchat.freenode.net/?channels=kong) |
[RefPlat Builds][kong-nightly-master]

## Summary

- [Summary](#summary)
- [Why Kong?](#why-kong)
- [Features](#features)
- [Distributions](#distributions)
- [Development](#development)
    - [Docker](#docker)
    - [Kong Gojira](#kong-gojira)
    - [Vagrant](#vagrant)
    - [Source Install](#source-install)
    - [Running for development](#running-for-development)
    - [Tests](#tests)
    - [Makefile](#makefile)
- [Enterprise Support & Demo](#enterprise-support--demo)
- [License](#license)

## Why Kong?

If you are building for the web, mobile, or IoT (Internet of Things) you will
likely end up needing common functionality to run your actual software. Kong
can help by acting as a gateway (or a sidecar) for microservices requests while
providing load balancing, logging, authentication, rate-limiting,
transformations, and more through plugins.


**Kong** or **Kong API Gateway** is a cloud-native, platform-agnostic, scalable API Gateway distinguished for its high performance and extensibility via plugins.

By providing functionality for proxying, routing, load balancing, health checking, authentication (and [more](#features)), Kong serves as the central layer for orchestrating microservices or conventional API traffic with ease.

Kong runs natively on Kubernetes thanks to its official [Kubernetes Ingress Controller](https://github.com/Kong/kubernetes-ingress-controller).

---

- **Cloud-Native**: Platform agnostic, Kong can run on any platform - from bare
  metal to containers - and it can run on every cloud natively.
- **Kubernetes-Native**: Declaratively configure Kong with native Kubernetes CRDs
  using the official Ingress Controller to route and connect all L4 + L7 traffic.
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
- **Security**: ACL, Bot detection, allow/deny IPs, etc...
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

- [Kubernetes Ingress Controller for Kong](https://github.com/Kong/kubernetes-ingress-controller):
  Use Kong for Kubernetes Ingress.
- [Kong Docker](https://github.com/Kong/docker-kong): A Dockerfile for
  running Kong in Docker.
- [Kong Packages](https://github.com/Kong/kong/releases): Pre-built packages
  for Debian, Red Hat, and OS X distributions (shipped with each release).
- [Kong Gojira](https://github.com/Kong/gojira): a tool for
  testing/developing multiple versions of Kong using containers.
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
- [Kong on IBM Cloud](https://github.com/andrew40404/installing-kong-IBM-cloud) - How to deploy Kong on IBM Cloud
- [Kong and Instaclustr](https://www.instaclustr.com/solutions/managed-cassandra-for-kong/): Let
  Instaclustr manage your Cassandra cluster.
- [Nightly Builds][kong-nightly-master]: Builds of the master branch available every morning at about 9AM PST.

You can find every supported distribution at the [official installation page](https://konghq.com/install/#kong-community).

## Development

We encourage community contributions to Kong. To make sure it is a smooth
experience (both for you and for the Kong team), please read
[CONTRIBUTING.md](CONTRIBUTING.md), [DEVELOPER.md](DEVELOPER.md),
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [COPYRIGHT](COPYRIGHT) before
you start.

If you are planning on developing on Kong, you'll need a development
installation. The `master` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development
Guide](https://docs.konghq.com/latest/plugin-development/), or browse an
online version of Kong's source code documentation in the [Plugin Development
Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/).

For a quick start with custom plugin development, check out [Pongo](https://github.com/Kong/kong-pongo)
and the [plugin template](https://github.com/Kong/kong-plugin) explained in detail below.

#### Docker

You can use Docker / docker-compose and a mounted volume to develop Kong by
following the instructions on [Kong/kong-build-tools](https://github.com/Kong/kong-build-tools#developing-kong).

#### Kong Gojira

[Gojira](https://github.com/Kong/gojira) is a CLI that uses docker-compose
internally to make the necessary setup of containers to get all
dependencies needed to run a particular branch of Kong locally, as well
as easily switching across versions, configurations and dependencies. It
has support for running Kong in Hybrid (CP/DP) mode, testing migrations,
running a Kong cluster, among other [features](https://github.com/Kong/gojira/blob/master/doc/manual.md).

#### Kong Pongo

[Pongo](https://github.com/Kong/kong-pongo) is another CLI like Gojira,
but specific for plugin development. It is docker-compose based and will
create local test environments including all dependencies. Core features
are running tests, integrated linter, config initialization, CI support,
and custom dependencies.

#### Kong Plugin Template

The [plugin template](https://github.com/Kong/kong-plugin) provides a basic
plugin and is considered a best-practices plugin repository. When writing
custom plugins we strongly suggest you start by using this repository as a
starting point. It contains the proper file structures, configuration files,
and CI setup to get up and running quickly. This repository seamlessly
integrates with [Pongo](https://github.com/Kong/kong-pongo).

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
$ git checkout master

# install the Lua sources
$ luarocks make
```

---

## Getting Started

Let’s test drive Kong by adding authentication to an API in under 5 minutes.

We suggest using the docker-compose distribution via the instructions below, but there is also a [docker installation](https://docs.konghq.com/gateway/latest/install/docker/#install-kong-gateway-in-db-less-mode) procedure if you’d prefer to run the Kong API Gateway in DB-less mode.

Whether you’re running in the cloud, on bare metal, or using containers, you can find every supported distribution on our [official installation](https://konghq.com/install/#kong-community) page.

1) To start, clone the Docker repository and navigate to the compose folder.
```cmd
  $ git clone https://github.com/Kong/docker-kong
  $ cd docker-kong/compose/
```

2) Start the Gateway stack using:
```cmd
  $ KONG_DATABASE=postgres docker-compose --profile database up
```

The Gateway will be available on the following ports on localhost:

`:8000` on which Kong listens for incoming HTTP traffic from your clients, and forwards it to your upstream services.
`:8001` on which the Admin API used to configure Kong listens.

Next, follow the [quick start guide](https://docs.konghq.com/gateway-oss/latest/getting-started/configuring-a-service/
) to tour the Gateway features.

## Features

By centralizing common API functionality across all your organization's services, the Kong API Gateway creates more freedom for engineering teams to focus on the challenges that matter most.

The top Kong features include:
- Advanced routing, load balancing, health checking - all configurable via a RESTful admin API or declarative configuration.
- Authentication and authorization for APIs using methods like JWT, basic auth, OAuth, ACLs and more.
- Proxy, SSL/TLS termination, and connectivity support for L4 or L7 traffic.
- Plugins for enforcing traffic controls, rate limiting, req/res transformations, logging, monitoring and including a plugin developer hub.
- Sophisticated deployment models like Declarative Databaseless Deployment and Hybrid Deployment (control plane/data plane separation) without any vendor lock-in.
- Native [ingress controller](https://github.com/Kong/kubernetes-ingress-controller) support for serving Kubernetes.

[![][kong-benefits]][kong-url]

### Plugin Hub
Plugins provide advanced functionality that extends the use of the Gateway. Many of the Kong Inc. and community-developed plugins like AWS Lambda, Correlation ID, and Response Transformer are showcased at the [Plugin Hub](https://docs.konghq.com/hub/).

Contribute to the Plugin Hub and ensure your next innovative idea is published and available to the broader community!

## Contributing

We ❤️ pull requests, and we’re continually working hard to make it as easy as possible for developers to contribute. Before beginning development with the Kong API Gateway, please familiarize yourself with the following developer resources:
- Contributor Guide ([CONTRIBUTING.md](CONTRIBUTING.md)) to learn about how to contribute to Kong.
- Development Guide ([DEVELOPER.md](DEVELOPER.md)): Setting up your development environment.
- [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md) and [COPYRIGHT](COPYRIGHT)

Use the [Plugin Development Guide](https://docs.konghq.com/latest/plugin-development/) for building new and creative plugins, or browse the online version of Kong's source code documentation in the [Plugin Development Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/). Developers can build plugins in [Lua](https://docs.konghq.com/gateway/latest/plugin-development/), [Go](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-go-plugins) or [JavaScript](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-javascript-plugins).

## Releases

Please see the [Changelog](CHANGELOG.md) for more details about a given release. The [SemVer Specification](https://semver.org) is followed when versioning Gateway releases.

## Join the Community

- Join the Kong discussions at the Kong Nation forum: [https://discuss.konghq.com/](https://discuss.konghq.com/)
- Follow us on Twitter: [https://twitter.com/thekonginc](https://twitter.com/thekonginc)
- Check out the docs: [https://docs.konghq.com/](https://docs.konghq.com/)
- Keep updated on YouTube by subscribing: [https://www.youtube.com/c/KongInc/videos](https://www.youtube.com/c/KongInc/videos)
- Read up on the latest happenings at our blog: [https://konghq.com/blog/](https://konghq.com/blog/)
- Visit our homepage to learn more: [https://konghq.com/](https://konghq.com/)

## Konnect Cloud

Kong Inc. offers commercial subscriptions that enhance the Kong API Gateway in a variety of ways. Customers of Kong's [Konnect Cloud](https://konghq.com/kong-konnect/) subscription take advantage of additional gateway functionality, commercial support, and access to Kong's managed (SaaS) control plane platform. The Konnect Cloud platform features include real-time analytics, a service catalog, developer portals, and so much more! [Get started](https://konghq.com/products/kong-konnect/register?utm_medium=Referral&utm_source=Github&utm_campaign=kong-gateway&utm_content=konnect-promo-in-gateway&utm_term=get-started) with Konnect Cloud.

## License

```
Copyright 2016-2023 Kong Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

[kong-url]: https://konghq.com/
[kong-logo]: https://konghq.com/wp-content/uploads/2018/05/kong-logo-github-readme.png
[kong-benefits]: https://konghq.com/wp-content/uploads/2018/05/kong-benefits-github-readme.png
[kong-nightly-master]: https://bintray.com/kong/kong-enterprise-edition-cloud-deb/ubuntu
[badge-travis-url]: https://travis-ci.org/Kong/kong-ee/branches
[badge-travis-image]: https://api.travis-ci.org/Kong/kong-ee.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master

[busted]: https://github.com/Olivine-Labs/busted
[luacheck]: https://github.com/mpeterv/luacheck
