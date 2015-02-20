#Overview

Welcome to the Kong official documentation, that will help you setting up Kong, configuring it and operating it. We reccomend reading every section of this document to have a full understanding of the project.

If you have more specific questions about Kong, please join our chat at <a href="irc://irc.freenode.net/kong">#kong</a> and the project maintainers will be happy to answer to your questions.

##What is Kong?

Kong is a scalable, lightweight, open source API Layer (also called *API Gateway* or *API Middleware*) that runs in front of any RESTful API and provides additional functionalities to the underlying APIs like authentication, analytics, monitoring, rate limiting and billing. Kong plugins provide extra functionality and services beyond the core Kong platform.

Built on top of reliable technologies like nginx and Cassandra, Kong is easy to setup and to scale - and by having an easy to use RESTful API, it's also easy to use.

Once Kong is running, every request being made to the API will hit Kong first, and then it will be proxied to the final API Because Kong can be easily scaled up and down there is no limit to the amount of requests it can serve, up to billions of HTTP requests.

![](/assets/images/docs/kong-simple.png)

Kong has been built following three foundamental principles:

* **Scalable**: it's easy to scale horizontally just by adding more machines. It can virtually handle any load.
* **Customizable**: it can be expanded by adding new features, and it's configurable through an internal RESTful API.
* **Runs on any infrastructure**: It can run in any cloud or on-premise environment, in a single or multi-datacenter setup, for any kind of API: public, private or invite-only APIs.

##How does it work?

Kong is made of two different components, that are easy to set up and to scale independently:

* The **API Proxy Server**, based on a modified version of the widely adopted **nginx** server, that processes the API requests.
* An underlying **Datastore** for storing operational data, **Apache Cassandra**, which is being used by major companies like Netflix, Comcast or Facebook and it's known for being highly scalable.

In order to work, Kong needs to have both these components set up and operational. A typical Kong installation can be summed up with the following picture:

![](/assets/images/docs/kong-detailed.png)

Don't worry if you are not experienced with these technologies, Kong works out of the box and you or your engineering team will be able to set it up quickly without issues.

### Api Proxy Server

The API Proxy Server, built on top of nginx, is the server that will actually process the API requests and execute the configured plugins to provide additional functionalities before finally proxying the request to the final API.

The Proxy Server listens on two ports, that by default are:

* Port `8000`, that will be used to process the API requests.
* Port `8001` provides the administration API that you can use to operate Kong, and should be private and firewalled.

The administration API is a RESTful service that can be used to configure Kong, create new users, and a handful of other operations. This makes it extremely easy to integrate Kong with existing systems, and it also enables beautiful user experiences: for example when implementing an api key provisioning flow, a website can directly communicate with Kong for the credentials provisioning.

### Datastore

Kong requires Apache Cassandra running alongside the Proxy Server. It is being used to store data that will be used by the Proxy Server to function properly, like APIs, Accounts and Applications data, besides metrics used internally. Kong won't function without a running Cassandra instance/cluster.

Cassandra has been chosen because is easy to scale up and down just by adding or removing nodes, and because it can be deployed in lots of different environments, from a single machine to a multi-datacenter cluster.

#Run it for the first time

Running Kong is very easy and will take a couple of minutes. To get started quickly choose between one of the following deployment options:

* [From source]()
* [Docker]()
* Vagrant: coming soon.
* AWS: coming soon.

##Plugins

One of the most important concept to understand are Kong Plugins. All the functionalities provided by Kong are served by easy to use **plugins**: authentication, rate-limiting, billing features are provided through an authentication plugin, a rate-limiting plugin, and a billing plugin among the others. You can decide which plugin to install and how to configure them through the Kong's RESTful internal API.

A plugin is code that can hook into the life-cycle of both requests and responses, with the additional possibility of changing their content, or interacting with third-party systems, thus allowing great customization. For example, a SOAP to REST converter plugin is totally possible with Kong.

By having plugins, Kong can be extended to fit any custom need or integration challenge. For example, if you need to integrate the API user authentication with a third-party enterprise security system, that would be implemented in a dedicated plugin that will run on every API request. More advanced users can build their own plugins, to extend the functionalities of Kong.

# Datastores

Technically Kong can be expanded to support many different datastores. Although this is a possiblity, for the time being we'll provide support for Cassandra, which is also the best option for starting small and scaling big.

In the future we may introduce support for SQL datastores like MySQL or Posgres, or for NoSQL databases like MongoDB.

# <a name="configuration"></a> Configuration

Kong comes with two configuration files that you can find in the `config.default` folder:

* `kong.yaml` stores Kong's configuration for communicating with the database, and for enabling/disabling plugins on the system.
* `nginx.conf` is the typical nginx configuration file that stores all the properties for the HTTP server

You will need to provide both files to run Kong.

# Scalability

When it comes down to scaling Kong, you need to keep in mind that you will need to scale both the API server and the underlying datastore.

## API Server

Scaling the API server up or down is very easy. Each server is stateless and you can just add or remove nodes under the load balancer. Under the hood the API server is built on top of nginx, and scaling is as simple as that.

Be aware that terminating a node might kill the ongoing API requests on that server, so you want to make sure that before killing an API Server all the HTTP requests have been already processed.

## Cassandra

Scaling Cassandra won't be required often, and usually a 2 nodes setup per datacenter is going to be enough for most of the use cases, but of course if your load is going to be very high then you might consider configuring it properly and prepare the cluster to be scaled in order to handle more requests.

The easy part is that Cassandra can be scaled up and down just by adding or removing nodes to the cluster, and the system will take care of re-balancing the data in the cluster.

# Internal API Endpoints

Kong offers a RESTful API that you can use to operate the system. You can run the API commands on any node in the cluster, and Kong will keep the configuration consistent across all the other servers. Below is the API documentation.

## API Object

The API object describes an API that's being exposed by Kong. In order to do that Kong needs to know what is going to be the DNS address that will be pointing to the API, and what is the final target URL of the API where the requests will be proxied. Kong can serve more than one API domain.

### Create API

`POST /apis/`

**Form Parameters**

* **name** - The name of the API
* **public_dns** - The public DNS address that will be pointing to the API. For example: *myapi.com*
* **target_url** - The base target URL that points to the API server, that will be used for proxying the requests. For example: *http://httpbin.org*

**Returns**

```json
HTTP 201 Created

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "name": "HttpBin",
    "public_dns": "my.api.com",
    "target_url": "http://httpbin.org",
    "created_at": 1422386534
}
```

### Retrieve API

`GET /apis/{id}`

* **id** - The ID of the API to retrieve

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "name": "HttpBin",
    "public_dns": "my.api.com",
    "target_url": "http://httpbin.org",
    "created_at": 1422386534
}
```

### List APIs

`GET /apis/`

**Querystring Parameters**

* id - The ID of the API
* name - The name of the API
* public_dns - The public DNS
* target_url - The target URL

**Returns**

```json
HTTP 200 OK

{
    "total": 2,
    "data": [
        {
            "id": "4d924084-1adb-40a5-c042-63b19db421d1",
            "name": "HttpBin",
            "public_dns": "my.api.com",
            "target_url": "http://httpbin.org",
            "created_at": 1422386534
        },
        {
            "id": "3f924084-1adb-40a5-c042-63b19db421a2",
            "name": "PrivateAPI",
            "public_dns": "internal.api.com",
            "target_url": "http://private.api.com",
            "created_at": 1422386585
        }
    ],
    "next": "http://localhost:8001/apis/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1",
    "previous": "http://localhost:8001/apis/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1"
}
```

### Update API

`PUT /apis/{id}`

* **id** - The ID of the API to update

**Body**

```json
{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "name": "HttpBin2",
    "public_dns": "my.api2.com",
    "target_url": "http://httpbin2.org",
    "created_at": 1422386534
}
```

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "name": "HttpBin2",
    "public_dns": "my.api2.com",
    "target_url": "http://httpbin2.org",
    "created_at": 1422386534
}
```


### Delete API

`DELETE /apis/{id}`

**Parameters**

* **id** - The ID of the API to delete

**Returns**

```json
HTTP 204 NO CONTENT
```

## Account Object

The Account object represents an account, or user, that can have one or more applications to consume the API objects. The Account object can be mapped with your database to keep consistency between Kong and your existing primary datastore.

### Create Account

`POST /accounts/`

**Form Parameters**

* provider_id - This is an optional field where you can store an existing ID for an Account, useful to map a Kong Account with a user in your existing database

**Returns**

```json
HTTP 201 Created

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "provider_id": "abc123",
    "created_at": 1422386534
}
```

### Retrieve Account

`GET /accounts/{id}`

* **id** - The ID of the Account to retrieve

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "provider_id": "abc123",
    "created_at": 1422386534
}
```

### List Accounts

`GET /accounts/`

**Querystring Parameters**

* id - The ID of the Account
* provider_id - The custom ID you set for the Account

**Returns**

```json
HTTP 200 OK

{
    "total": 2,
    "data": [
        {
            "id": "4d924084-1adb-40a5-c042-63b19db421d1",
            "provider_id": "abc123",
            "created_at": 1422386534
        },
        {
            "id": "3f924084-1adb-40a5-c042-63b19db421a2",
            "provider_id": "def345",
            "created_at": 1422386585
        }
    ],
    "next": "http://localhost:8001/accounts/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1",
    "previous": "http://localhost:8001/accounts/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1"
}
```

### Update Account

`PUT /accounts/{id}`

* **id** - The ID of the Account to update

**Body**

```json
{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "provider_id": "updated_abc123",
    "created_at": 1422386534
}
```

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "provider_id": "updated_abc123",
    "created_at": 1422386534
}
```


### Delete Account

`DELETE /accounts/{id}`

**Parameters**

* **id** - The ID of the Account to delete

**Returns**

```json
HTTP 204 NO CONTENT
```

## Application Object

The Application object represents an application belonging to an existing Account, and stores credentials for consuming the API objects. An Account can have more than one Application. An Application can represent one or more API keys, for example.

### Create Application

`POST /applications/`

**Form Parameters**

* **account_id** - The Account ID of an existing Account whose this application belongs to.
* **secret_key** - This is where the secret credential, like an API key or a password, will be stored. It is required.
* public_key - Some authentication types require both a public and a secret key. This field is reserved for public keys, and can be empty if not used.

**Returns**

```json
HTTP 201 Created

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "secret_key": "SECRET-xaWijqenkln81jA",
    "public_key": "PUBLIC-08landkl123sa",
    "created_at": 1422386534
}
```

### Retrieve Application

`GET /applications/{id}`

* **id** - The ID of the Application to retrieve

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "secret_key": "SECRET-uajZwmSnLHBiRGb",
    "public_key": "PUBLIC-74YmAGcirwkMdS6",
    "created_at": 1422386534
}
```

### List Applications

`GET /accounts/`

**Querystring Parameters**

* id - The ID of the Application
* account_id - The ID of the Account
* public_key - The public key to lookup
* secret_key - The secret key to lookup

**Returns**

```json
HTTP 200 OK

{
    "total": 2,
    "data": [
        {
            "id": "4d924084-1adb-40a5-c042-63b19db421d1",
            "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
            "secret_key": "SECRET-uajZwmSnLHBiRGb",
            "public_key": "PUBLIC-74YmAGcirwkMdS6",
            "created_at": 1422386534
        },
        {
            "id": "3f924084-1adb-40a5-c042-63b19db421a2",
            "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
            "secret_key": "SECRET-4hvoM6xcHMLb6QK",
            "public_key": "PUBLIC-y5JlLqGeswN2JcB",
            "created_at": 1422386585
        }
    ],
    "next": "http://localhost:8001/applications/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1",
    "previous": "http://localhost:8001/applications/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1"
}
```

### Update Application

`PUT /applications/{id}`

* **id** - The ID of the Application to update

**Body**

```json
{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "secret_key": "UPDATED-SECRET-uajZwmSnLHBiRGb",
    "public_key": "UPDATED-PUBLIC-74YmAGcirwkMdS6",
    "created_at": 1422386534
}
```

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "account_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "secret_key": "UPDATED-SECRET-uajZwmSnLHBiRGb",
    "public_key": "UPDATED-PUBLIC-74YmAGcirwkMdS6",
    "created_at": 1422386534
}
```


### Delete Application

`DELETE /applications/{id}`

**Parameters**

* **id** - The ID of the Application to delete

**Returns**

```json
HTTP 204 NO CONTENT
```

## Plugin Object

The Plugin object represents a plugin that will be executed during the HTTP request/response workflow, and it's how Kong adds functionalities to an API, like Authentication or Rate Limiting. Plugins have a configuration `value` field that requires a JSON object representing the plugin configuration. By default creating a plugin and adding it to an API will enforce the same rules to every Application consuming the API. Sometimes the plugin configuration needs to be tuned to different values for some specific applications, for example when the Rate Limiting for an API is set to 20 requests per minute, but it needs to be increased for some specific Applications. In Kong it's possible to do that by creating a new Plugin object specifying the optional `application_id` field.

### Create Plugin

`POST /plugins/`

**Form Parameters**

* **name** - The name of the Plugin that's going to be added. The Plugin should have already been installed in every Kong server separately.
* **api_id** - The API ID that the Plugin will target
* **value** - The JSON configuration required for the Plugin. Each Plugin will have different configuration fields, so check the realtive Plugin documentation to know which fields you can set.
* application_id - An optional Application ID to customize the Plugin behavior when an incoming request is being sent by the specified Application. This configuration takes precedence over the global API configuration.

**Returns**

```json
HTTP 201 Created

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "application_id": "a3dX2dh2-1adb-40a5-c042-63b19dbx83hF4",
    "name": "ratelimiting",
    "value": "{\"limit\": 20, \"period\":\"minute\"}",
    "created_at": 1422386534
}
```

### Retrieve Plugin

`GET /plugins/{id}`

* **id** - The ID of the Plugin to retrieve

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "application_id": "a3dX2dh2-1adb-40a5-c042-63b19dbx83hF4",
    "name": "ratelimiting",
    "value": "{\"limit\": 20, \"period\":\"minute\"}",
    "created_at": 1422386534
}
```

### List Plugins

`GET /accounts/`

**Querystring Parameters**

* id - The ID of the Plugin
* name - The name of the Plugin
* api_id - The ID of the API
* application_id - The ID of the Application

**Returns**

```json
HTTP 200 OK

{
    "total": 2,
    "data": [
        {
            "id": "4d924084-1adb-40a5-c042-63b19db421d1",
            "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
            "name": "ratelimiting",
            "value": "{\"limit\": 20, \"period\":\"minute\"}",
            "created_at": 1422386534
        },
        {
            "id": "3f924084-1adb-40a5-c042-63b19db421a2",
            "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
            "application_id": "a3dX2dh2-1adb-40a5-c042-63b19dbx83hF4",
            "name": "ratelimiting",
            "value": "{\"limit\": 300, \"period\":\"hour\"}",
            "created_at": 1422386585
        }
    ],
    "next": "http://localhost:8001/plugins/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1",
    "previous": "http://localhost:8001/plugins/?limit=10&offset=4d924084-1adb-40a5-c042-63b19db421d1"
}
```

### Update Plugin

`PUT /plugins/{id}`

* **id** - The ID of the Plugin to update

**Body**

```json
{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "application_id": "a3dX2dh2-1adb-40a5-c042-63b19dbx83hF4",
    "name": "ratelimiting",
    "value": "{\"limit\": 50, \"period\":\"second\"}",
    "created_at": 1422386534
}
```

**Returns**

```json
HTTP 200 OK

{
    "id": "4d924084-1adb-40a5-c042-63b19db421d1",
    "api_id": "5fd1z584-1adb-40a5-c042-63b19db49x21",
    "application_id": "a3dX2dh2-1adb-40a5-c042-63b19dbx83hF4",
    "name": "ratelimiting",
    "value": "{\"limit\": 50, \"period\":\"second\"}",
    "created_at": 1422386534
}
```


### Delete Plugin

`DELETE /plugins/{id}`

**Parameters**

* **id** - The ID of the Plugin to delete

**Returns**

```json
HTTP 204 NO CONTENT
```