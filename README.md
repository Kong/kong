# Microservice & API Management Layer

[![Gitter Badge][gitter-badge]][gitter-url]

[![][kong-logo]][kong-url]

Kong was created at [Mashape][mashape-url] to secure, manage and extend Microservices & APIs, while handling billions of requests per month. Kong is powered by the battle-tested tech of **NGINX** with a focus on scalability, high performance & reliability. 

[Website](http://getkong.org) |
[Documentation](http://getkong.org/docs) |
[Installation](http://getkong.org/install) |
[Mailing List](https://groups.google.com/forum/#!forum/konglayer) 


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
  - **Analytics**: Visualize, Inspect and Monitor API traffic with [Mashape Analytics](https://apianalytics.com).
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

We've load tested Kong and Cassandra on AWS; you can see our [benchmark report here](http://getkong.org/about/benchmark/).

## Distributions

Kong comes in many shapes. While this repository contains its core's source code, other repos are also under active development:

- [Kong Docker](https://github.com/Mashape/docker-kong): A Dockerfile for running Kong in Docker.
- [Kong Vagrant](https://github.com/Mashape/kong-vagrant): A Vagrantfile for provisioning a development ready environment for Kong.
- [Kong Homebrew](https://github.com/Mashape/homebrew-kong): Homebrew Formula for Kong.
- [Kong CloudFormation](https://github.com/Mashape/kong-dist-cloudformation): Kong in a 1-click deployment for AWS EC2
- [Kong AWS AMI](https://aws.amazon.com/marketplace/pp/B014GHERVU/ref=srh_res_product_image?ie=UTF8&sr=0-2&qid=1440801656966): Kong AMI on the AWS Marketplace.
- [Kong Packages](https://github.com/Mashape/kong-distributions): Packaging scripts for deb, rpm and osx distributions.

## Community Resources and Tools 

Resources:

- [Kong mentioned for the Empire PaaS](http://engineering.remind.com/introducing-empire/)  
- [Kong Getting Started Tutorials in Japanese](http://dev.classmethod.jp/etc/kong-api-aggregator/)
- [Configuring Kong](http://rotlogix.com/2015/06/18/configuring-kong-for-a-services-layer/)
- [Realtime API Management with Pushpin](http://blog.fanout.io/2015/07/14/realtime-api-management-pushpin-kong/)
- [How to Create your own Plugin](http://streamdata.io/blog/developing-an-helloworld-kong-plugin/)
- [Instaclustr Partners with Kong](https://www.instaclustr.com/instaclustr-partners-with-mashape-to-deliver-managed-cassandra-for-kong/)



Tools:

- [Kong on Tutum](https://github.com/Sillelien/docker-kong)
- [Kong Admin GUI in JS](https://github.com/rsdevigo/jungle) 
- [Kong Admin GUI in Py](https://github.com/vikingco/django-kong-admin)
- [Chef Cookbook for Kong](https://github.com/zuazo/kong-cookbook)
- [Python Client for Kong API](https://pypi.python.org/pypi/python-kong/)
- [Kong with Instaclustr](https://www.instaclustr.com/products/kong/)




## Roadmap

You can find a detailed Roadmap of Kong on the [Wiki](https://github.com/Mashape/kong/wiki).

## Development 

[![Build Status][travis-badge]][travis-url]
[![Circle CI][circleci-badge]][circleci-url]

If you are planning on developing on Kong (writing your own plugin or contribute to the core), you'll need a development installation.

#### Vagrant

You can use a Vagrant box running Kong and Cassandra that you can find at [Mashape/kong-vagrant](https://github.com/Mashape/kong-vagrant).

#### Source Install

First, you will need to already have Kong installed. Install Kong by following one of the methods described at [getkong.org/download](http://getkong.org/download). Then, make sure you have downloaded [Cassandra](http://cassandra.apache.org/download/) and that it is running. These steps will override your Kong installation with the latest source from the master branch:

```shell
$ git clone https://github.com/Mashape/kong
$ cd kong/

# Build and install Kong globally using Luarocks, overriding the version previously installed
$ [sudo] make install

# Install all development dependencies and create your environment configuration files
$ make dev

# Finally, run Kong with the just created development configuration
$ kong start -c kong_DEVELOPMENT.yml
```

The `lua_package_path` directive in the configuration specifies that the Lua code in your local folder will be used in favor of the system installation. The `lua_code_cache` directive being turned off, you can start Kong, edit your local files, and test your code without restarting Kong.

#### Makefile Operations

When developing, use the `Makefile` for doing the following operations:

| Name          | Description                                                              |
| -------------:| -------------------------------------------------------------------------|
| `install`     | Install the Kong luarock globally                                        |
| `dev`         | Setup your development environment                                       |
| `clean`       | Clean your development environment                                       |
| `start`       | Start the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)             |
| `restart`     | Restart the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)           |
| `seed`        | Seed the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)              |
| `drop`        | Drop the `DEVELOPMENT` environment (`kong_DEVELOPMENT.yml`)              |
| `lint`        | Lint Lua files in `kong/` and `spec/`                                    |
| `test`        | Run the unit tests                                                       |
| `test-integration` | Run the integration tests (Kong + DAO)                               |
| `test-plugins` | Run unit + integration tests of all plugins                              |
| `test-all`    | Run all unit + integration tests at once                                 |
| `coverage`    | Run all tests + coverage report                                          |

## Enterprise Support

Support, Demo, Training, API Certifications and Consulting available at http://getkong.org/enterprise.

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

[kong-url]: http://getkong.org/
[kong-docs]: http://getkong.org/docs/

[kong-logo]: http://i.imgur.com/4jyQQAZ.png
[kong-benefits]: http://cl.ly/image/1B3J3b3h1H1c/Image%202015-07-07%20at%206.57.25%20PM.png

[mashape-url]: https://www.mashape.com

[travis-url]: https://travis-ci.org/Mashape/kong
[travis-badge]: https://img.shields.io/travis/Mashape/kong.svg?style=flat

[circleci-url]: https://circleci.com/gh/Mashape/kong
[circleci-badge]: https://circleci.com/gh/Mashape/kong.svg?style=shield

[gitter-url]: https://gitter.im/Mashape/kong
[gitter-badge]: https://img.shields.io/badge/Gitter-Join%20Chat-blue.svg

[google-groups-url]: https://groups.google.com/forum/#!forum/konglayer
