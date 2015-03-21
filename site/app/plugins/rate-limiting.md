---
title: Plugins - Rate Limiting
sitemap: true
show_faq: true
layout: page
id: page-plugin
header_title: Rate Limiting
header_icon: /assets/images/icons/plugins/rate-limiting.png
header_caption: utilities
breadcrumbs:
  Plugins: /plugins
  Rate Limiting: /plugins/rate-limiting/
---

---

#### Rate limit how many HTTP requests a developer can make in a given period of seconds, minutes, hours, days months or years. If the API has no authentication layer, the client IP address will be used, otherwise the application credential will be used.

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
$ kong install ratelimiting
```

Add the plugin to the list of available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```yaml
plugins_available:
  - ratelimiting
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```bash
curl -d "name=ratelimiting&api_id=API_ID&value.limit=1000&value.period=hour" http://kong:8001/plugins/
```

| parameter                    | description                                                |
|------------------------------|------------------------------------------------------------|
| name                         | The name of the plugin to use, in this case: `tcplog`   |
| api_id                       | The API ID that this plugin configuration will target             |
| *application_id*             | Optionally the APPLICATION ID that this plugin configuration will target |
| `value.limit`           | The amount of HTTP requests the developer can make in the given period of time |
| `value.period`           | Can be one between: `second`, `minute`, `hour`, `day`, `month`, `year` |
