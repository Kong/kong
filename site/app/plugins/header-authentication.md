---
title: Plugins - Header Authentication
sitemap: true
show_faq: true
layout: page
id: page-plugin
header_title: Header Authentication
header_icon: /assets/images/icons/plugins/header-authentication.png
header_caption: authentication
breadcrumbs:
  Plugins: /plugins
  Header Authentication: /plugins/header-authentication/
---

---

#### Add Header Authentication to your APIs, where the credentials will be parsed from the request headers

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
$ kong install headerauth
```

Add the plugin to the list of available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```yaml
plugins_available:
  - headerauth
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```bash
curl -d "name=headerauth&api_id=API_ID&value.header_names=header_name1, header_name2&value.hide_credentials=true" http://kong:8001/plugins/
```

| parameter                    | description                                                |
|------------------------------|------------------------------------------------------------|
| name                         | The name of the plugin to use, in this case: `headerauth`   |
| api_id                       | The API ID that this plugin configuration will target             |
| *application_id*             | Optionally the APPLICATION ID that this plugin configuration will target |
| `value.header_names`                  | Describes an array of comma separated header names where the plugin will look for a valid credential. The client must send the authentication key in one of those headers. For example: *x-apikey*  |
| `value.hide_credentials`           | Default `false`. An optional boolean value telling the plugin to hide the credential to the final API server. It will be removed by Kong before proxying the request |
