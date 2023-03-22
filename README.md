[![][kong-logo]][kong-url]

![Stars](https://img.shields.io/github/stars/Kong/kong?style=flat-square) ![GitHub commit activity](https://img.shields.io/github/commit-activity/m/Kong/kong?style=flat-square) ![Docker Pulls](https://img.shields.io/docker/pulls/_/kong?style=flat-square) [![Build Status][badge-action-image]][badge-action-url] ![Version](https://img.shields.io/github/v/release/Kong/kong?color=green&label=Version&style=flat-square)  ![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square)  ![Twitter Follow](https://img.shields.io/twitter/follow/thekonginc?style=social)


**Kong** or **Kong API Gateway** is a cloud-native, platform-agnostic, scalable API Gateway distinguished for its high performance and extensibility via plugins.

By providing functionality for proxying, routing, load balancing, health checking, authentication (and [more](#features)), Kong serves as the central layer for orchestrating microservices or conventional API traffic with ease.

Kong runs natively on Kubernetes thanks to its official [Kubernetes Ingress Controller](https://github.com/Kong/kubernetes-ingress-controller).

---

[Installation](https://konghq.com/install/#kong-community) | [Documentation](https://docs.konghq.com) | [Discussions](https://github.com/Kong/kong/discussions) | [Forum](https://discuss.konghq.com) | [Blog](https://konghq.com/blog) | [Builds][kong-master-builds]

---

## Getting Started

Let’s test drive Kong by adding authentication to an API in under 5 minutes.

We suggest using the getting started script located in our [docs](https://docs.konghq.com/gateway/latest/get-started/). 

Whether you’re running in the cloud, on bare metal, or using containers, you can find every supported distribution on our [installation options] (https://docs.konghq.com/gateway/latest/install/) page.


## Features

Kong Gateway is a lightweight, fast, and flexible cloud-native API gateway. An API gateway is a reverse proxy that lets you manage, configure, and route requests to your APIs.

Kong Gateway runs in front of any RESTful API and can be extended through modules and plugins. It’s designed to run on decentralized architectures, including hybrid-cloud and multi-cloud deployments.

With Kong Gateway, users can:

- Leverage workflow automation and modern GitOps practices
- Decentralize applications/services and transition to microservices
- Create a thriving API developer ecosystem
- Proactively identify API-related anomalies and threats
- Secure and govern APIs/services, and improve API visibility across the entire organization.
- Native [ingress controller](https://github.com/Kong/kubernetes-ingress-controller) support for serving Kubernetes.

Visit the the [Features](https://docs.konghq.com/gateway/latest/#features) section for detailed list of features, including which are OSS vs. Enterprise.  

### Plugin Hub
Plugins provide advanced functionality that extends the use of the Gateway. Many of the Kong Inc. and community-developed plugins like AWS Lambda, Correlation ID, and Response Transformer are showcased at the [Plugin Hub](https://docs.konghq.com/hub/). 

Contribute to the Plugin Hub and ensure your next innovative idea is published and available to the broader community!

## Contributing

We ❤️ pull requests, and we’re continually working hard to make it as easy as possible for developers to contribute. Before beginning development with the Kong API Gateway, please familiarize yourself with the following developer resources:
- Contributor Guide ([CONTRIBUTING.md](CONTRIBUTING.md)) to learn about how to contribute to Kong.
- Development Guide ([DEVELOPER.md](DEVELOPER.md)): Setting up your development environment.
- [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md) and [COPYRIGHT](COPYRIGHT)

Use the [Plugin Development Guide](https://docs.konghq.com/latest/plugin-development/) for building new and creative plugins, or browse the online version of Kong's source code documentation in the [Plugin Development Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/). Developers can build plugins in [Lua](https://docs.konghq.com/gateway-oss/latest/plugin-development/), [Go](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-go-plugins) or [JavaScript](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-javascript-plugins).

## Releases

Please see the [Changelog](CHANGELOG.md) for more details about a given release. The [SemVer Specification](https://semver.org) is followed when versioning Gateway releases.

## Join the Community

- Join the Kong discussions at the Kong Nation forum: [https://discuss.konghq.com/](https://discuss.konghq.com/)
- Follow us on Twitter: [https://twitter.com/thekonginc](https://twitter.com/thekonginc)
- Check out the docs: [https://docs.konghq.com/](https://docs.konghq.com/)
- Keep updated on YouTube by subscribing: [https://www.youtube.com/c/KongInc/videos](https://www.youtube.com/c/KongInc/videos)
- Read up on the latest happenings at our blog: [https://konghq.com/blog/](https://konghq.com/blog/)
- Visit our homepage to learn more: [https://konghq.com/](https://konghq.com/)

## Konnect

Konnect is designed to provide three primary benefits to complement the existing capabilities of the Kong Gateway:

- **Simplify the operation of running Kong Gateway instances**: By providing SaaS-hosted Control planes through the concept of a Runtime Group. A Runtime Group is effectively a virtual Kong Gateway control plane provided as a service with 99.99% SLA. Konnect Runtime Groups can be provisioned in seconds via a single UI click or API call.
- **Enable governance of multiple Kong Gateway deployments across different teams, geographies, clouds, or environments at scale**: The Konnect Runtime Manager combined with Konnect’s powerful Authorization capabilities enable multiple teams within an organization to access their Kong Gateway environments with just the right level of access, while central teams can have a full view of all deployments for governance purposes.
- **Provide a Services Catalog (called Service Hub), API Portal, and API Analytics capabilities as a service**: With Konnect, all of these capabilities are available for all Kong Gateway deployments with zero additional operational complexity.

There are many reasons users of Kong’s open source gateway should consider migrating to Konnect to achieve a production-ready, highly-available, distributed API gateway in a very rapid time frame. Read more about [Konnect](https://docs.konghq.com/konnect/) or sign up to [get started](https://konghq.com/products/kong-konnect/register?utm_medium=Referral&utm_source=Github&utm_campaign=kong-gateway&utm_content=konnect-promo-in-gateway&utm_term=get-started).

## License

```
Copyright 2016-2023 Kong Inc.

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
