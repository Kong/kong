# Microservice & API Management Layer
[![][kong-logo]][kong-url]

Kong runs in production at [Mashape](https://www.mashape.com) to secure, manage and extend over [15,000 APIs](http://stackshare.io/mashape/how-mashape-manages-over-15-000-apis-microservices), while handling billions of requests per month. Kong is backed by the battle-tested **NGINX** with a focus on scalability, high performance & reliability.

[Website](http://getkong.org) |
[Documentation](http://getkong.org/docs) |
[Installation](http://getkong.org/install) |
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

We've load tested Kong and Cassandra on AWS; you can see our [benchmark report here](http://getkong.org/about/benchmark/).

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

You can read more about writing your own plugins in the [Plugin Development Guide](https://getkong.org/docs/latest/plugin-development/), or browse an online version of Kong's source code documentation in the [Public Lua API Reference](https://getkong.org/docs/0.5.x/lua-reference/).

#### Vagrant

You can use a Vagrant box running Kong and Cassandra that you can find at [Mashape/kong-vagrant](https://github.com/Mashape/kong-vagrant).

#### Source Install

First, you will need to already have Kong installed. Install Kong by following one of the methods described at [getkong.org/download](http://getkong.org/download). Then, make sure you have downloaded [Cassandra](http://cassandra.apache.org/download/) and that it is running. These steps will override your Kong installation with the latest source code:

```shell
# clone the repo and use the next branch
$ git clone https://github.com/Mashape/kong
$ cd kong/
$ git checkout next

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

[kong-logo]: http://i.imgur.com/4jyQQAZ.png
[kong-benefits]: http://cl.ly/image/1B3J3b3h1H1c/Image%202015-07-07%20at%206.57.25%20PM.png

[mashape-url]: https://www.mashape.com

[gitter-url]: https://gitter.im/Mashape/kong
[gitter-badge]: https://img.shields.io/badge/Gitter-Join%20Chat-blue.svg

[google-groups-url]: https://groups.google.com/forum/#!forum/konglayer
