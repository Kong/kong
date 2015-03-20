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

#### The Query Authentication plugin allows you to specify a query based authentication layer for your APIs.

---

## Installation

Make sure every Kong server in your cluster has the required dependency by executing:

```bash
kong install queryauth
```

Add the plugin to the list of the available plugins on every Kong server in your cluster by editing the “kong.yml” configuration file

```bash
# available plugins on this server
plugins_available:
- queryauth
```

## Usage

Using the plugin is straightforward, you can add it on top of an API by executing the following request on your Kong server:

```
curl -d ‘name=queryauth&api_id=API_ID&key_names=apikey&hide_credentials=true' http://kong:8001/plugins/
```

| parameter             | description                                            |
|-----------------------|--------------------------------------------------------|
| name                  | The name of the plugin to use, in this case: queryauth |
| api_id                | The API ID where we want to install the plugin         |
| `key_names`           | Describes an array of parameter names where the system will look fro a credential. The client must send the authentication key in one of those key names |
| `hide_credentials`    | A boolean value telling the system to hide the credential to the final API server. It will be removed by Kong before proxying the request. |
