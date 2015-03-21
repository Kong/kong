---
title: Plugins - Query Authentication
sitemap: true
show_faq: true
layout: page
id: page-plugin
header_title: Query Authentication
header_icon: /assets/images/icons/plugins/query-authentication.png
header_caption: authentication
breadcrumbs:
  Plugins: /plugins
  Query Authentication: /plugins/query-authentication/
---

---

#### Add query authentication like API-Keys to your APIs, either in the querystring, as a form parameter or as JSON property.

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
$ kong install queryauth
```

Add the plugin to the list of available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```yaml
plugins_available:
  - queryauth
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```bash
curl -d "name=queryauth&api_id=API_ID&value.key_names=key_name1, key_name2&value.hide_credentials=true" http://kong:8001/plugins/
```

| parameter                    | description                                                |
|------------------------------|------------------------------------------------------------|
| name                         | The name of the plugin to use, in this case: `queryauth`   |
| api_id                       | The API ID that this plugin configuration will target             |
| *application_id*             | Optionally the APPLICATION ID that this plugin configuration will target |
| `value.key_names`                  | Describes an array of comma separated parameter names where the plugin will look for a valid credential. The client must send the authentication key in one of those key names, and the plugin will try to read the credential from the querystring, or a form parameter, or a json property (in this order). For example: *apikey*  |
| `value.hide_credentials`           | Default `false`. An optional boolean value telling the plugin to hide the credential to the final API server. It will be removed by Kong before proxying the request |
