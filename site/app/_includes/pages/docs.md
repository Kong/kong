#Overview

Welcome to the Kong official documentation, that will help you setting up Kong, configuring it and operating it. We reccomend reading every section of this document to have a full understanding of the project.

If you have more specific questions about Kong, please join our chat at #kong and the project maintainers will be happy to answer to your questions.

Kong is trusted by more than 100,000 developers, processing billions of requests for more than 10,000 public and private APIs around the world.

##What is Kong?

Kong is an open-source enterprise API Layer (also called *API Gateway* or *API Middleware*) that runs in front of any RESTful API and provides additional functionalities like authentication, analytics, monitoring, rate limiting and billing without changing the source code of the API itself. It is a foundamental technology that any API provider should leverage to deliver better APIs without reinventing the wheel.

Every request being made to the API will hit Kong first, and then it will be proxied to the final API with an average processing latency that is usually lower than **8ms** per request. Because Kong can be easily scaled up and down there is no limit to the amount of requests it can serve, up to billions of HTTP requests.

![](/assets/images/docs/kong-simple.png)

Kong has been built following three foundamental principles:

* **Scalable**: it's easy to scale horizontally just by adding more machines. It can virtually handle any load.
* **Customizable**: it can be expanded by adding new features, and it's configurable through an internal RESTful API.
* **Runs on any infrastructure**: It can run in any cloud or on-premise environment, in a single or multi-datacenter setup, for any kind of API: public, private and partner APIs.

##Plugins

All the functionalities provided by Kong are served by easy to use **plugins**: authentication, rate-limiting, billing features are provided through an authentication plugin, a rate-limiting plugin, and a billing plugin among the others. You can decide which plugin to install and how to configure them through the Kong's RESTful internal API.

A plugin is code that can hook into the life-cycle of both requests and responses, with the additional possibility of changing their content, thus allowing great customization. For example, a SOAP to REST converter plugin is totally possible with Kong.

By having plugins, Kong can be extended to fit any custom need or integration challenge. For example, if you need to integrate the API user authentication with a third-party enterprise security system, that would be implemented in a dedicated plugin that will run on every API request. More advanced users can build their own plugins, to extend the functionality of Kong.

##How does it work?

Kong is made of two different components, that are easy to set up and to scale independently:

* The **API Proxy Server**, based on a modified version of the widely adopted **nginx** server, that processes the API requests.
* An underlying **Datastore** for storing operational data, **Apache Cassandra**, which is being used by major companies like Netflix, Comcast or Facebook and it's known for being highly scalable.

In order to work, Kong needs to have both these components set up and operational. A typical Kong installation can be summed up with the following picture:

![](/assets/images/docs/kong-detailed.png)

### Api Proxy Server

The API Proxy Server is the component that will actually process the API requests and execute the configured plugins to provide additional functionalities. It is also the component that will invoke the final API.

The proxy server also offers an internal API that can be used to configure Kong, create new users, and a handful of other operations. This makes it extremely easy to integrate Kong with existing systems, and it also enables beautiful user experiences: for example when implementing an api key provisioning flow, a website can directly communicate with Kong for the credentials provisioning.

### Datastore

Kong requires Apache Cassandra running alongside the Proxy Server. It is being used to store data that will be used by the Proxy Server to function properly, like APIs, Accounts and Applications data, besides metrics used internally. Kong won't function without a running Cassandra instance/cluster.

Cassandra has been chosen because is easy to scale up and down just by adding or removing nodes, and because it can be deployed in lots of different environments, from a single machine to a multi-datacenter cluster.

#Run it for the first time

Running Kong is very easy and will take a couple of minutes. To get started quickly choose between one of the following deployment options:

* [From source]()
* [Docker]()
* [Vagrant]()
* [AWS Image]()

The Docker, Vagrant and AWS deployment options will already start a local Apache Cassandra instance. This is great for testing Kong, but once you go to production we reccomend having dedicated servers/instances for your Cassandra cluster.

# <a name="configuration"></a> Configuration

Configuration here

# Internal API Endpoints



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