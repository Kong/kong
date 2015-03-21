---
title: Plugins - TCP Log
sitemap: true
show_faq: true
layout: page
id: page-plugin
header_title: TCP Log
header_icon: /assets/images/icons/plugins/tcp-log.png
header_caption: logging
breadcrumbs:
  Plugins: /plugins
  TCP Log: /plugins/tcp-log/
---

---

#### Log request and response data to a TCP server

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
$ kong install tcplog
```

Add the plugin to the list of available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```yaml
plugins_available:
  - tcplog
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```bash
curl -d "name=tcplog&api_id=API_ID&value.host=127.0.0.1&value.port=9999&value.timeout=1000&value.keepalive=1000" http://kong:8001/plugins/
```

| parameter                    | description                                                |
|------------------------------|------------------------------------------------------------|
| name                         | The name of the plugin to use, in this case: `tcplog`   |
| api_id                       | The API ID that this plugin configuration will target             |
| *application_id*             | Optionally the APPLICATION ID that this plugin configuration will target |
| `value.host`           | The IP address or host name to send data to |
| `value.port`           | The port to send data to on the final server |
| `value.timeout`           | Default `10000`. An optional timeout in milliseconds when sending data to the final server|
| `value.keepalive`           | Default `60000`. An optional value in milliseconds that defines for how long an idle connection will live before being closed|
