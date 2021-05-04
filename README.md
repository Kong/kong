[![][kong-logo]][kong-url]

![Stars](https://img.shields.io/github/stars/Kong/kong?style=flat-square) ![Issues](https://img.shields.io/github/issues/Kong/kong?style=flat-square) ![Forks](https://img.shields.io/github/forks/Kong/kong?style=flat-square)


**Kong** or **Kong Gateway** is a cloud-native, platform-agnostic, scalable API Gateway distinguished for its high performance and extensibility via plugins.

By providing functions for load balancing, authenticating, rate-limiting, active/passive health checking, caching, reverse proxying (and many others), the Kong Gateway can achieve more than your traditional web servers. When you deploy Kong, it becomes the central layer for orchestrating microservices or conventional API traffic with ease.

## Getting Started

Let’s test drive the Gateway by adding authentication to an API in under 5 minutes.

We suggest using the docker-compose distribution via the instructions below, but there is also a [docker installation](https://docs.konghq.com/install/docker/) procedure if you’d prefer to run Kong Gatewayin a DB-less mode. 

Whether you’re running in the cloud, on bare metal or using containers, you can find every supported distribution on the [official installation](https://konghq.com/install/#kong-community) page.

1) Clone the Docker repository and navigate to the compose folder
```cmd
  $ git clone https://github.com/Kong/docker-kong
  $ cd /compose
```

2) Start the Kong Gateway stack using:
```cmd
$ docker-compose up
```

The Gateway will be available on the following ports on localhost:
`:8000` on which Kong listens for incoming HTTP traffic from your clients, and forwards it to your upstream services.
`:8001` on which the Admin API used to configure Kong listens.

Next, follow the [quick start guide](https://docs.konghq.com/gateway-oss/latest/getting-started/configuring-a-service/
) to tour the Gateway features

## Features

The Kong Gateway creates more developer freedom by taking care of the common functionality across your entire service layer. In this way, engineering teams can focus more on solving business challenges without repeatedly implementing the same features in each API. 

Some uses of the Gateway include:
- Building in identity authentication like JWT, basic auth and more.
- Enforcing request rate & size limits globally, based on the endpoint or the authenticated identity.
- Support multi-cloud, hybrid cloud, lift & shift deployment models without any vendor lock-in.
- Scaling deployments by horizontally adding more nodes. Advanced Control Plane/Data plane architectures for administering many gateways.
- Unifying observability across a suite of microservices with components like Prometheus, Zipkin, etc.
- Transcoding HTTP to gRPC and gRPC proxy with the Gateway's native gRPC support
- Deploying as a native ingress controller to serve Kubernetes clusters around route/connect all L4 + L7 traffic.

[![][kong-benefits]][kong-url]

### Plugin Hub
Plugins provide advanced functionality that extends the use of the Gateway. Many of the Kong Inc. and community-developed plugins like AWS Lambda, Correlation ID, and Response Transformer are showcased at the [Plugin Hub](https://docs.konghq.com/hub/). 

Contribute to the Plugin Hub and ensure your next innovative plugin is published and available to the broader community!

## Contributing

We ❤️  pull requests, and we’re continually working hard to make it as easy as possible for developers to contribute. Before beginning development with the Kong Gateway, please familiarize yourself with the following developer resources:
- [CONTRIBUTING.md](https://github.com/Kong/kong/blob/master/CONTRIBUTING.md),
- [DEVELOPER.md](https://github.com/Kong/kong/blob/master/DEVELOPER.md),
- [CODE_OF_CONDUCT.md](https://github.com/Kong/kong/blob/master/CODE_OF_CONDUCT.md), and [COPYRIGHT](https://github.com/Kong/kong/blob/master/COPYRIGHT)

Use the [Plugin Development Guide](https://docs.konghq.com/latest/plugin-development/) for building new and creative plugins, or browse the online version of Kong's source code documentation in the [Plugin Development Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/). You can build plugins in Lua, Go or JavaScript.

## Join the Community

- Join the Kong discussions at the Kong Nation forum: [https://discuss.konghq.com/](https://discuss.konghq.com/)
- Follow us on Twitter: [https://twitter.com/thekonginc](https://twitter.com/thekonginc)
- Check out the docs: [https://docs.konghq.com/](https://docs.konghq.com/)
- Keep updated on youtube by subscribing: [https://www.youtube.com/c/KongInc/videos](https://www.youtube.com/c/KongInc/videos)
- Read up on the latest happening at our blog: [https://konghq.com/blog/](https://konghq.com/blog/)
- Visit our homepage to learn more: [https://konghq.com/](https://konghq.com/)

## Konnect
[Konnect](https://konghq.com/kong-konnect/) provides a managed platform for API connectivity through a hosted control plane. Operate and deploy high performance connectivity runtimes on any cloud provider or your own data centers. Platform features include: real-time analytics, service catalog, developer portals, insomnia integration and so much more! [Get started](https://konghq.com/get-started/) with Konnect.

## License

```
Copyright 2016-2021 Kong Inc.

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
[kong-master-builds]: https://hub.docker.com/r/kong/kong/tags
[badge-action-url]: https://github.com/Kong/kong/actions
[badge-action-image]: https://github.com/Kong/kong/workflows/Build%20&%20Test/badge.svg

[busted]: https://github.com/Olivine-Labs/busted
[luacheck]: https://github.com/mpeterv/luacheck
