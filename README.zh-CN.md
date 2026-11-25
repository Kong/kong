[![][kong-logo]][kong-url]

![Stars](https://img.shields.io/github/stars/Kong/kong?style=flat-square) ![GitHub commit activity](https://img.shields.io/docker/pulls/_/kong?style=flat-square) [![Build Status][badge-action-image]][badge-action-url] ![Version](https://img.shields.io/github/v/release/Kong/kong?color=green&label=Version&style=flat-square)  ![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square) [![Twitter Follow](https://img.shields.io/twitter/follow/thekonginc?style=social)](https://x.com/thekonginc)

> 本文档是 [README.md](README.md) 的中文翻译，若两者有出入以英文原版为准。

Kong（即 Kong Gateway）是一个云原生、与平台无关、可伸缩的 **API 𖧹 LLM 𖧹 MCP** 网关，以高性能和通过插件实现的可扩展性而著称。它还提供先进的 AI 流量能力，包括多 LLM 支持、语义安全、MCP 流量安全与分析等。

通过提供代理、路由、负载均衡、健康检查、认证（以及[更多功能](#功能特性)），Kong 成为编排微服务或传统 API 流量——乃至智能体式 LLM 与 MCP 流量——的核心层，让这一切变得轻而易举。

得益于官方 [Kubernetes Ingress Controller](https://github.com/Kong/kubernetes-ingress-controller)，Kong 可以原生运行在 Kubernetes 上。

<br />

[![][kong-diagram]][kong-url]

---

[安装](https://konghq.com/install/#kong-community) | [文档](https://docs.konghq.com) | [讨论区](https://github.com/Kong/kong/discussions) | [论坛](https://discuss.konghq.com) | [博客](https://konghq.com/blog) | [构建版本][kong-master-builds] | [AI 网关](https://konghq.com/products/kong-ai-gateway) | [云托管 Kong](https://konghq.com/kong-konnect/) | <a href="README.md">English</a>

---

## 快速上手

如果你更倾向于使用云托管的 Kong，可以[注册 Kong Konnect 免费试用](https://konghq.com/products/kong-konnect/register?utm_medium=Referral&utm_source=Github&utm_campaign=kong-gateway&utm_content=konnect-promo-in-gateway&utm_term=get-started)，几分钟内即可上手。否则，可以按照下面的说明，在你自己的基础设施上开始使用 Kong。

让我们通过在 5 分钟内为一个 API 添加认证来试驾一下 Kong。

我们建议按照下面的说明使用 docker-compose 发行版；如果你希望以 DB-less 模式运行 Kong Gateway，也可以参考 [docker 安装](https://docs.konghq.com/gateway/latest/install/docker/#install-kong-gateway-in-db-less-mode)流程。

无论你是在云上、裸机上还是使用容器运行，都可以在我们的[官方安装](https://konghq.com/install/#kong-community)页面找到所有受支持的发行版。

1) 首先，克隆 Docker 仓库并进入 compose 目录。
```cmd
  $ git clone https://github.com/Kong/docker-kong
  $ cd docker-kong/compose/
```

2) 使用以下命令启动 Gateway 技术栈：
```cmd
  $ KONG_DATABASE=postgres docker-compose --profile database up
```

现在可以在本机的以下端口访问 Gateway：

- `:8000` - 通过 Kong 将流量发送到你的服务
- `:8001` - 使用 Admin API 或 [decK](https://github.com/kong/deck) 配置 Kong
- `:8002` - 在 [localhost:8002](http://localhost:8002) 访问 Kong 的管理 Web UI（[Kong Manager](https://github.com/Kong/kong-manager)）

接下来，按照[快速入门指南](https://docs.konghq.com/gateway-oss/latest/getting-started/configuring-a-service/
)浏览 Gateway 的各项功能。

### AI Gateway 快速上手（LLM 与 MCP）

如果你想开始使用 Kong AI Gateway 的能力（包括 LLM 和 MCP 特性），请参阅[官方 AI 文档](https://developer.konghq.com/ai-gateway/)。

## 功能特性

通过将组织内所有服务的通用 API、AI 和 MCP 功能集中管理，Kong Gateway 让工程团队获得更多自由，专注于最重要的挑战。

Kong 的主要特性包括：

- 高级路由、负载均衡、健康检查——全部可通过 RESTful 管理 API 或声明式配置进行配置。
- 使用 JWT、Basic 认证、OAuth、ACL 等方式对 API 进行认证与授权。
- 通用 LLM API，可在 OpenAI、Anthropic、GCP Gemini、AWS Bedrock、Azure AI、Databricks、Mistral、Huggingface 等多家提供商之间路由。
- MCP 流量治理、MCP 安全和 MCP 可观测性，并支持从任意 RESTful API 自动生成 MCP。
- 60 多项 AI 特性，如 AI 可观测性、语义安全与缓存、语义路由等。
- 代理、SSL/TLS 终结，以及对 L4 或 L7 流量的连接支持。
- 用于实施流量控制、限流、请求/响应转换、日志、监控的插件，并提供插件开发者中心。
- 成熟的部署模型，如声明式无数据库部署和混合部署（控制平面/数据平面分离），且没有任何厂商锁定。
- 原生 [ingress controller](https://github.com/Kong/kubernetes-ingress-controller) 支持，服务 Kubernetes。

[![][kong-benefits]][kong-url]

### 插件中心（Plugin Hub）

插件提供扩展 Gateway 用途的高级功能。许多由 Kong Inc. 和社区开发的插件（如 AWS Lambda、Correlation ID 和 Response Transformer）都展示在[插件中心](https://docs.konghq.com/hub/)。

为插件中心做贡献，让你的下一个创新想法发布并惠及更广泛的社区！

## 参与贡献

我们 ❤️ pull request，并一直在努力让开发者的贡献尽可能简单。在开始 Kong Gateway 的开发之前，请先熟悉以下开发者资源：

- 社区承诺（[COMMUNITY_PLEDGE.md](COMMUNITY_PLEDGE.md)）：我们与你——开源社区——互动的承诺。
- 贡献者指南（[CONTRIBUTING.md](CONTRIBUTING.md)）：了解如何为 Kong 做贡献。
- 开发指南（[DEVELOPER.md](DEVELOPER.md)）：搭建你的开发环境。
- [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md) 和 [COPYRIGHT](COPYRIGHT)

使用[插件开发指南](https://docs.konghq.com/latest/plugin-development/)构建新颖而富有创意的插件，或在[插件开发工具包（PDK）参考](https://docs.konghq.com/latest/pdk/)中在线浏览 Kong 的源代码文档。开发者可以使用 [Lua](https://docs.konghq.com/gateway/latest/plugin-development/)、[Go](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-go-plugins) 或 [JavaScript](https://docs.konghq.com/gateway-oss/latest/external-plugins/#developing-javascript-plugins) 构建插件。

## 版本发布

有关某个版本的更多细节，请查看[变更日志](CHANGELOG.md)。Gateway 的版本发布遵循[语义化版本规范（SemVer）](https://semver.org)。

## 加入社区

- 查阅[文档](https://docs.konghq.com/)
- 加入 [Kong 讨论区](https://github.com/Kong/kong/discussions)
- 在 Kong Nation 论坛参与 Kong 讨论：[https://discuss.konghq.com/](https://discuss.konghq.com/)
- 加入我们的[社区 Slack](http://kongcommunity.slack.com/)
- 在我们的[博客](https://konghq.com/blog/)上了解最新动态
- 在 [X](https://x.com/thekonginc) 上关注我们
- 订阅我们的 [YouTube 频道](https://www.youtube.com/c/KongInc/videos)
- 访问我们的[主页](https://konghq.com/)了解更多

## Konnect Cloud

Kong Inc. 提供以多种方式增强 Kong Gateway 的商业订阅。Kong [Konnect Cloud](https://konghq.com/kong-konnect/) 订阅的客户可以享受额外的网关功能、商业支持，以及访问 Kong 托管的（SaaS）控制平面平台。Konnect Cloud 平台特性包括实时分析、服务目录、开发者门户等等！[立即开始](https://konghq.com/products/kong-konnect/register?utm_medium=Referral&utm_source=Github&utm_campaign=kong-gateway&utm_content=konnect-promo-in-gateway&utm_term=get-started)使用 Konnect Cloud。

## 许可证

```
Copyright 2016-2026 Kong Inc.

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
[kong-diagram]: https://assets.prd.mktg.konghq.com/images/2025/09/68cc1bfd-kong-diagram.png?v=2
[kong-benefits]: https://konghq.com/wp-content/uploads/2018/05/kong-benefits-github-readme.png
[kong-master-builds]: https://hub.docker.com/r/kong/kong/tags
[badge-action-url]: https://github.com/Kong/kong/actions
[badge-action-image]: https://github.com/Kong/kong/actions/workflows/build_and_test.yml/badge.svg?branch=master&event=push

[busted]: https://github.com/Olivine-Labs/busted
[luacheck]: https://github.com/mpeterv/luacheck