---
title: Plugins - Basic Authentication
sitemap: true
show_faq: true
layout: page
id: page-plugin
header_title: Basic Authentication
header_icon: /assets/images/icons/plugins/basic-authentication.png
header_caption: authentication
breadcrumbs:
  Plugins: /plugins
  Basic Authentication: /plugins/basic-authentication/
---

---

#### Add Basic Authentication to your APIs, with username and password protection.

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
$ kong install basicauth
```

Add the plugin to the list of available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```yaml
plugins_available:
  - basicauth
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```bash
curl -d "name=basicauth&api_id=API_ID&value.hide_credentials=true" http://kong:8001/plugins/
```

| parameter                    | description                                                |
|------------------------------|------------------------------------------------------------|
| name                         | The name of the plugin to use, in this case: `basicauth`   |
| api_id                       | The API ID that this plugin configuration will target             |
| *application_id*             | Optionally the APPLICATION ID that this plugin configuration will target |
| `value.hide_credentials`           | Default `false`. An optional boolean value telling the plugin to hide the credential to the final API server. It will be removed by Kong before proxying the request |
