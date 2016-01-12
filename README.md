# Microservice & API Management Layer
[![][kong-logo]][kong-url]

Kong runs in production at [Mashape][mashape-url] to secure, manage and extend over [15,000 APIs](http://stackshare.io/mashape/how-mashape-manages-over-15-000-apis-microservices), while handling billions of requests per month. Kong is backed by the battle-tested **NGINX** with a focus on scalability, high performance & reliability.

[Website][kong-url] |
[Documentation](https://getkong.org/docs) |
[Installation](https://getkong.org/install) |
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
- [**Enterprise Support**](#enterprise-support)
- [**License**](#license)

## Features

- **CLI**: Control your Kong cluster from the command line just like Neo in The Matrix.
- **REST API**: Kong can be operated with its RESTful API for maximum flexibility.
- **Geo-Replicated**: Configs are always up-to-date across different regions.
- **Scalability**: Distributed by nature, Kong scales horizontally simply by adding nodes.
- **Performance**: Kong handles load with ease by scaling and using NGINX at the core.
- **Plugins**: Extendable architecture for adding functionality to Kong and APIs.
  - **OAuth2.0**: Add easily an OAuth2.0 authentication to your APIs.
  - **Logging**: Log requests and responses to your system over HTTP, TCP, UDP or to disk.
  - **JWT**: Verify and authenticate JSON Web Tokens.
  - **HMAC**: Add HMAC Authentication to your APIs.
  - **ACL**: Acccess Control for your API Consumers.
  - **IP-restriction**: Whitelist or blacklist IPs that can make requests.
  - **Response-Rate-Limiting**: Rate limiting based on custom response header value.
  - **Analytics**: Visualize, Inspect and Monitor API traffic with [Galileo](https://getgalileo.io).
  - **SSL**: Setup a specific SSL certificate for an underlying service or API.
  - **Monitoring**: Live monitoring provides key load and performance server metrics.
  - **Authentication**: Manage consumer credentials query string and header tokens.
  - **Rate-limiting**: Block and throttle requests based on IP, authentication or body size.
  - **Transformations**: Add, remove or manipulate HTTP requests and responses.
  - **CORS**: Enable cross-origin requests to your APIs that would otherwise be blocked.
  - **Anything**: Need custom functionality? Extend Kong with your own Lua plugins!

For more info about plugins, you can check out the [Plugin Gallery](https://getkong.org/plugins/).

## Why Kong?

If you're building for web, mobile or IoT (Internet of Things) you will likely end up needing common functionality on top of your actual software. Kong can help by acting as a gateway for HTTP requests while providing logging, authentication, rate-limiting and more through plugins.

[![][kong-benefits]][kong-url]

## Benchmarks

We've load tested Kong and Cassandra on AWS; you can see our [benchmark report here](https://getkong.org/about/benchmark/).

## Distributions

Kong comes in many shapes. While this repository contains its core's source code, other repos are also under active development:

- [Kong Docker](https://github.com/Mashape/docker-kong): A Dockerfile for running Kong in Docker.
- [Kong Packages](https://github.com/Mashape/kong-distributions): Packaging scripts for deb, rpm and osx distributions.
- [Kong Vagrant](https://github.com/Mashape/kong-vagrant): A Vagrantfile for provisioning a development ready environment for Kong.
- [Kong Homebrew](https://github.com/Mashape/homebrew-kong): Homebrew Formula for Kong.
- [Kong CloudFormation](https://github.com/Mashape/kong-dist-cloudformation): Kong in a 1-click deployment for AWS EC2
- [Kong AWS AMI](https://aws.amazon.com/marketplace/pp/B014GHERVU/ref=srh_res_product_image?ie=UTF8&sr=0-2&qid=1440801656966): Kong AMI on the AWS Marketplace.
- [Kong on Microsoft Azure](https://github.com/Mashape/kong-azure): Run Kong using Azure Resource Manager.


## Community Resources and Tools

Resources:

- [The story behind Kong](http://stackshare.io/mashape/how-mashape-manages-over-15-000-apis-microservices)
- [Kong mentioned for the Empire PaaS](http://engineering.remind.com/introducing-empire/)
- [Realtime API Management with Pushpin](http://blog.fanout.io/2015/07/14/realtime-api-management-pushpin-kong/)
- [How to create your own Kong plugin](http://streamdata.io/blog/developing-an-helloworld-kong-plugin/)
- [Instaclustr partners with Kong](https://www.instaclustr.com/instaclustr-partners-with-mashape-to-deliver-managed-cassandra-for-kong/)
- [How to deploy Kong on Azure](https://jeremiedevillard.wordpress.com/2015/10/12/deploy-kong-api-management-using-azure-resource-manager/)
- [Kong intro in Portuguese](https://www.youtube.com/watch?v=0OIWr1yLs_4)
- [Kong tutorial in Japanese 1](http://dev.classmethod.jp/etc/kong-api-aggregator/)
- [Kong tutorial in Japanese 2](http://www.ryuzee.com/contents/blog/7048)
- [HAProxy + Kong](http://47ron.in/blog/2015/10/23/haproxy-in-the-era-of-microservices.html)
- [Learn Lua in 15 minutes](http://tylerneylon.com/a/learn-lua/)

Videos:

- [VIDEO - Kong Demo in Portuguese](https://www.youtube.com/watch?v=0OIWr1yLs_4)
- [VIDEO - OAuth2 with Kong](https://www.youtube.com/watch?v=nzySsFuV72M)
- [VIDEO - Kong with Docker](https://www.youtube.com/watch?v=ME7MI2SwJ-E)

Podcasts:
- [Changelog #185](https://changelog.com/185)
- [Three Devs and a Maybe #83](http://threedevsandamaybe.com/kong-the-api-microservice-management-layer-with-ahmad-nassri/)

Tools:

- [Kong Dashboard](https://github.com/PGBI/kong-dashboard)
- [Kongfig](https://github.com/mybuilder/kongfig)
- [Kongfig on Puppet Forge](https://forge.puppetlabs.com/mybuilder/kongfig)
- [Konga CLI Tool](https://github.com/Floby/konga-cli)
- [Kong on Tutum](https://github.com/Sillelien/docker-kong)
- [Kong GUI in JS](https://github.com/rsdevigo/jungle)
- [Kong GUI in Py](https://github.com/vikingco/django-kong-admin)
- [Kong UI](https://github.com/msaraf/kong-ui)
- [Chef Cookbook for Kong](https://github.com/zuazo/kong-cookbook)
- [Python Client for Kong](https://pypi.python.org/pypi/python-kong/)
- [Kong with Instaclustr](https://www.instaclustr.com/products/kong/)
- [.NET Client for Kong](https://www.nuget.org/packages/Kong/0.0.4)

## Roadmap

You can find a detailed Roadmap of Kong on the [Wiki](https://github.com/Mashape/kong/wiki).

## Development

If you are planning on developing on Kong, you'll need a development installation. The `next` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development Guide](https://getkong.org/docs/latest/plugin-development/), or browse an online version of Kong's source code documentation in the [Public Lua API Reference](https://getkong.org/docs/latest/lua-reference/).

#### Vagrant

You can use a Vagrant box running Kong and Cassandra that you can find at [Mashape/kong-vagrant](https://github.com/Mashape/kong-vagrant).

#### Source Install

First, you will need to already have Kong installed. Install Kong by following one of the methods described at [getkong.org/download](https://getkong.org/download). Then, make sure you have downloaded [Cassandra](http://cassandra.apache.org/download/) and that it is running. These steps will override your Kong installation with the latest source code:

```shell
$ git clone https://github.com/Mashape/kong
$ cd kong/

# You might want to switch to the development branch. See CONTRIBUTING.md for more infos
$ git checkout next

# Install latest Kong globally using Luarocks, overriding the version previously installed
$ make install
```

#### Running for development

It is best to run Kong with a development configuration file. Such a file can easily be created following those instructions:

```shell
# Install all development dependencies and create your environment configuration files
$ make dev

# Finally, run Kong with the just created development configuration
$ kong start -c kong_DEVELOPMENT.yml
```

Since you use a configuration file dedicated to development, feel free to customize it as you wish. For example, the one generated by `make dev` includes the following changes: the [`lua_package_path`](https://github.com/openresty/lua-nginx-module#lua_package_path) directive specifies that the Lua modules in your current directory will be used in favor of the system installation. The [`lua_code_cache`](https://github.com/openresty/lua-nginx-module#lua_code_cache) directive being turned off, you can start Kong, edit your local files, and test your code without restarting Kong.

To stop Kong, you will need to specify the configuration file too:

```shell
$ kong stop -c kong_DEVELOPMENT.yml
# or
$ kong reload -c kong_DEVELOPMENT.yml
```

Learn more about the CLI and configuration options in the [documentation](https://getkong.org/docs/latest/cli/).

#### Tests

Kong relies on three test suites:

* Unit tests
* Integration tests, which require a running Cassandra cluster
* Plugins tests, which are a mix of unit and integration tests, which also require a Cassandra cluster

The first can simply be run after installing [busted](https://github.com/Olivine-Labs/busted) and running:

```
$ busted spec/unit
```

The integration tests require you to have a configuration file at `./kong_TEST.yml` and to make it point to a running Cassandra cluster (it will use a keyspace of its own). Such a file is also created by `make dev`, but you can create one of your own or customize it (you might want to change the logging settings, for example):

```
$ busted spec/integration
```

The `make dev` command can create a default `kong_TEST.yml` file.

The plugins tests also require a `./kong_TEST.yml` file and a running Cassandra cluster, and be be run with:

```
$ busted spec/plugins
```

Finally, all suites can be run at once by simply running `busted`.

#### Tools

Various tools are used for documentation and code quality. They can all be easily installed by running:

```
$ make dev
```

Code coverage is analyzed by [luacov](http://keplerproject.github.io/luacov/) from the busted **unit tests**:

```
$ busted --coverage
$ luacov kong
# or
$ make coverage
```

The code is statically analyzed and linted by [luacheck](https://github.com/mpeterv/luacheck). It is easier to use the Makefile to run it:

```
$ make lint
```

The documentation is written according to the [ldoc](https://github.com/stevedonovan/LDoc) format and can be generated with:

```
$ ldoc -c config.ld kong/
# or
$ make doc
```

We maintain this documentation on the  [Public Lua API Reference](https://getkong.org/docs/latest/lua-reference/) so it is unlikely that you will have to generate it, but it is useful to keep that information in mind when documenting your modules if you wish to contribute.

#### Makefile

When developing, you can use the `Makefile` for doing the following operations:

| Name               | Description                                             |
| ------------------:| --------------------------------------------------------|
| `install`          | Install the Kong luarock globally                       |
| `dev`              | Setup your development environment                      |
| `clean`            | Clean your development environment                      |
| `doc`              | Generate the ldoc documentation                         |
| `lint`             | Lint Lua files in `kong/` and `spec/`                   |
| `test`             | Run the unit tests suite                                |
| `test-integration` | Run the integration tests suite                         |
| `test-plugins`     | Run the plugins test suite                              |
| `test-all`         | Run all unit + integration tests at once                |
| `coverage`         | Run all tests + coverage report                         |

## Enterprise Support

Support, Demo, Training, API Certifications and Consulting available at https://getkong.org/enterprise.

## License

```
Copyright 2015 Mashape, Inc

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

