# API Gateway & Microservice Management [![Build Status][badge-travis-image]][badge-travis-url]
[![][kong-logo]][kong-url]

Kong is a scalable, open source API Layer *(also known as an API Gateway, or
API Middleware)*. Kong was originally built at [Mashape][mashape-url] to
secure, manage and extend over
[15,000 Microservices](http://stackshare.io/mashape/how-mashape-manages-over-15000-apis-and-microservices)
for its API Marketplace, which generates billions of requests per month.

Backed by the battle-tested **NGINX** with a focus on high performance, Kong
was made available as an open-source platform in 2015. Under active
development, Kong is now used in production at hundreds of organizations from
startups, to large enterprises and government departments including: The New
York Times, Expedia, Healthcare.gov, The Guardian, Condè Nast and The
University of Auckland.

[Website][kong-url] |
[Docs](https://getkong.org/docs) |
[Installation](https://getkong.org/install) |
[Blog](http://blog.mashape.com/category/kong/) |
[Mailing List][google-groups-url] |
[Gitter Chat][gitter-url] |
freenode: [#kong](http://webchat.freenode.net/?channels=kong)

## Summary

- [**Features**](#features)
- [**Why Kong?**](#why-kong)
- [**Benchmarks**](#benchmarks)
- [**Distributions**](#distributions)
- [**Community Resources and Tools**](#community-resources-and-tools)
- [**Roadmap**](#roadmap)
- [**Development**](#development)
- [**Enterprise Support & Demo**](#enterprise-support--demo)
- [**License**](#license)

## Features

- **CLI**: Control your Kong cluster from the command line just like Neo in The
  Matrix.
- **REST API**: Kong can be operated with its RESTful API for maximum
  flexibility.
- **Geo-Replicated**: Configs are always up-to-date across different regions.
- **Failure Detection & Recovery**: Kong is unaffected if one of your Cassandra
  nodes goes down.
- **Cluster Awareness**: All Kongs auto-join the cluster keeping config updated
  across nodes.
- **Scalability**: Distributed by nature, Kong scales horizontally simply by
  adding nodes.
- **Performance**: Kong handles load with ease by scaling and using NGINX at
  the core.
- **Developer Portal**: With
  [Gelato](https://docs.gelato.io/guides/using-gelato-with-kong) integration,
  build beautiful portals for easy developer on-boarding.
- **Plugins**: Extendable architecture for adding functionality to Kong and APIs.
  - **OAuth2.0**: Add easily an OAuth2.0 authentication to your APIs.
  - **Logging**: Log requests and responses to your system over HTTP, TCP, UDP or to disk.
  - **JWT**: Verify and authenticate JSON Web Tokens.
  - **HMAC**: Add HMAC Authentication to your APIs.
  - **ACL**: Acccess Control for your API Consumers.
  - **IP-restriction**: Whitelist or blacklist IPs that can make requests.
  - **Response-Rate-Limiting**: Rate limiting based on custom response header value.
  - **API Analytics**: Visualize, Inspect and Monitor API traffic with [Galileo](https://getgalileo.io).
  - **Loggly Integration**: Push your traffic data through your Loggly account.
  - **DataDog Integration**: Easy Data monitoring through DataDog. DevOps will love it!
  - **Runscope Integration**: Test and Monitor your APIs.
  - **Syslog**: Logging to System log.
  - **SSL**: Setup a Specific SSL Certificate for an underlying service or API.
  - **Monitoring**: Live monitoring provides key load and performance server metrics.
  - **Authentication**: Manage consumer credentials query string and header tokens.
  - **Rate-limiting**: Block and throttle requests based on IP, authentication or body size.
  - **Transformations**: Add, remove or manipulate HTTP requests and responses.
  - **CORS**: Enable cross-origin requests to your APIs that would otherwise be blocked.
  - **Anything**: Need custom functionality? Extend Kong with your own Lua plugins!

For more info about plugins, you can check out the [Plugin
Gallery](https://getkong.org/plugins/).

## Why Kong?

If you're building for web, mobile or IoT (Internet of Things) you will likely
end up needing common functionality on top of your actual software. Kong can
help by acting as a gateway for HTTP requests while providing logging,
authentication, rate-limiting and more through plugins.

[![][kong-benefits]][kong-url]

## Benchmarks

We've load tested Kong and Cassandra on AWS; you can see our [benchmark report
here](https://getkong.org/about/benchmark/).

## Distributions

Kong comes in many shapes. While this repository contains its core's source
code, other repos are also under active development:

- [Kong Docker](https://github.com/Mashape/docker-kong): A Dockerfile for
  running Kong in Docker.
- [Kong Packages](https://github.com/Mashape/kong/releases): Pre-built packages
  for Debian, Red Hat, and OS X distributions (shipped with each release).
- [Kong Vagrant](https://github.com/Mashape/kong-vagrant): A Vagrantfile for
  provisioning a development ready environment for Kong.
- [Kong Homebrew](https://github.com/Mashape/homebrew-kong): Homebrew Formula
  for Kong.
- [Kong CloudFormation](https://github.com/Mashape/kong-dist-cloudformation):
  Kong in a 1-click deployment for AWS EC2
- [Kong AWS AMI](https://aws.amazon.com/marketplace/pp/B014GHERVU): Kong AMI on
  the AWS Marketplace.
- [Kong on Microsoft Azure](https://github.com/Mashape/kong-dist-azure): Run Kong
  using Azure Resource Manager.
- [Kong on Heroku](https://github.com/heroku/heroku-kong): Deploy Kong on
  Heroku in one click.
- [Kong and Instaclustr](https://www.instaclustr.com/solutions/kong/): Let
  Instaclustr manage your Cassandra cluster.

## Community Resources and Tools

**Resources**:
- [The story behind Kong](http://stackshare.io/mashape/how-mashape-manages-over-15000-apis-and-microservices)
- [Kong mentioned for the Empire PaaS](http://engineering.remind.com/introducing-empire/)
- [Realtime API Management with Pushpin](http://blog.fanout.io/2015/07/14/realtime-api-management-pushpin-kong/)
- [How to create your own Kong plugin](http://streamdata.io/blog/developing-an-helloworld-kong-plugin/)
- [Instaclustr partners with Kong](https://www.instaclustr.com/blog/2015/09/16/instaclustr-partners-with-mashape-to-deliver-managed-cassandra-for-kong/)
- [How to deploy Kong on Azure](https://jeremiedevillard.wordpress.com/2015/10/12/deploy-kong-api-management-using-azure-resource-manager/)
- [Kong intro in Portuguese](https://www.youtube.com/watch?v=0OIWr1yLs_4)
- [Kong tutorial in Japanese 1](http://dev.classmethod.jp/etc/kong-api-aggregator/)
- [Kong tutorial in Japanese 2](http://www.ryuzee.com/contents/blog/7048)
- [HAProxy + Kong](http://47ron.in/blog/2015/10/23/haproxy-in-the-era-of-microservices.html)
- [Learn Lua in 15 minutes](http://tylerneylon.com/a/learn-lua/)
- [A Question about Microservices](http://marcotroisi.com/questions-about-microservices/)
- [Kong Intro in Chinese](https://www.sdk.cn/news/1596)

**Videos**:
- [Kong Intro Tutorial](https://www.youtube.com/watch?v=S6CeWL2qvl4)
- [Kong mentioned at Hashicorp Conf](https://www.youtube.com/watch?v=0r24K_0BGBY&feature=youtu.be&t=22m03s)
- [Kong Demo in Portuguese](https://www.youtube.com/watch?v=0OIWr1yLs_4)
- [OAuth2 with Kong](https://www.youtube.com/watch?v=nzySsFuV72M)
- [Kong with Docker](https://www.youtube.com/watch?v=ME7MI2SwJ-E)

**Podcasts**:
- [Changelog #185](https://changelog.com/185)
- [Three Devs and a Maybe #83](http://threedevsandamaybe.com/kong-the-api-microservice-management-layer-with-ahmad-nassri/)

Here is a list of third-party **tools** maintained by the community:
- [Ansible role for Kong on Ubuntu](https://github.com/Getsidecar/ansible-role-kong)
- [Biplane](https://github.com/articulate/biplane): declarative configuration in Crystal
- [Bonobo](https://github.com/guardian/bonobo): key management (with Mashery migration scripts)
- [Chef cookbook](https://github.com/zuazo/kong-cookbook)
- [Django Kong Admin](https://github.com/vikingco/django-kong-admin): Admin UI in Python
- [Jungle](https://github.com/rsdevigo/jungle): Admin UI in JavaScript
- [Kong Dashboard](https://github.com/PGBI/kong-dashboard): Admin UI in JavaScript
- [Kong for CanopyCloud](https://github.com/CanopyCloud/cip-kong)
- [Kong image waiting for Cassandra](https://github.com/articulate/docker-kong-wait)
- [Kong image for Tutum](https://github.com/Sillelien/docker-kong)
- [Kong-UI](https://github.com/msaraf/kong-ui): Admin UI in JavaScript
- [Konga](https://github.com/Floby/konga-cli): CLI Admin tool in JavaScript
- [Konga](https://pantsel.github.io/konga/): Another elegant Kong UI in Javascript
- [Kongfig](https://github.com/mybuilder/kongfig): Declarative Kong configuration in YAML, JSON, or JavaScript
- [Kongfig on Puppet Forge](https://forge.puppet.com/mybuilder/kongfig)
- [Puppet recipe](https://github.com/scottefein/puppet-nyt-kong)
- [Puppet module on Puppet Forge](https://forge.puppet.com/juniorsysadmin/kong)
- [Python-Kong](https://pypi.python.org/pypi/python-kong/): Admin client library for Python
- [.NET-Kong](https://www.nuget.org/packages/Kong/0.0.4): Admin client library for .NET
- [kong-java-client](https://github.com/vaibhav-sinha/kong-java-client): Admin client library for Java

## Roadmap

You can find a detailed Roadmap of Kong on the [Wiki](https://github.com/Mashape/kong/wiki).

## Development

If you are planning on developing on Kong, you'll need a development
installation. The `next` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development
Guide](https://getkong.org/docs/latest/plugin-development/), or browse an
online version of Kong's source code documentation in the [Public Lua API
Reference](https://getkong.org/docs/latest/lua-reference/).

#### Vagrant

You can use a Vagrant box running Kong and Postgres that you can find at
[Mashape/kong-vagrant](https://github.com/Mashape/kong-vagrant).

#### Source Install

Kong mostly is an OpenResty application made of Lua source files, but also
requires some additional third-party dependencies. We recommend installing
those by following the source install instructions at
https://getkong.org/install/source/.

Instead of following the second step (Install Kong), clone this repository
and install the latest Lua sources instead of the currently released ones:

```shell
$ git clone https://github.com/Mashape/kong
$ cd kong/

# you might want to switch to the development branch. See CONTRIBUTING.md
$ git checkout next

# install the Lua sources
$ luarocks make
```

#### Running for development

Check out the [development section](https://github.com/Mashape/kong/blob/next/kong.conf.default#L244)
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

[Learn more](https://getkong.org/enterprise) about Kong Priority Support,
Products, HA, Demo, Training, API Certifications and Professional Services.

## License

```
Copyright 2016-2017 Kong Inc.

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

[kong-url]: https://getkong.org/
[mashape-url]: https://www.mashape.com
[kong-logo]: http://i.imgur.com/4jyQQAZ.png
[kong-benefits]: http://cl.ly/image/1B3J3b3h1H1c/Image%202015-07-07%20at%206.57.25%20PM.png
[gitter-url]: https://gitter.im/Mashape/kong
[gitter-badge]: https://img.shields.io/badge/Gitter-Join%20Chat-blue.svg
[google-groups-url]: https://groups.google.com/forum/#!forum/konglayer
[badge-travis-url]: https://travis-ci.org/Mashape/kong/branches
[badge-travis-image]: https://travis-ci.org/Mashape/kong.svg?branch=master

[busted]: https://github.com/Olivine-Labs/busted
[luacheck]: https://github.com/mpeterv/luacheck
[Luarocks]: https://luarocks.org

