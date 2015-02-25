# Starting Kong

This screencast shows how to run Kong for the first time using [Docker](https://www.docker.com/). You can find the Docker instructions on the [official Kong Docker repository](https://github.com/Mashape/docker-kong).

<script type="text/javascript" src="https://asciinema.org/a/16960.js" id="asciicast-16960" async data-speed="2"></script>

# Adding an API

In this screencast we'll learn how to add an API on Kong. Specifically we'll add the HttpBin API on Kong.

Adding an API on Kong is the first step in using Kong, after APIs have been added in the system we can add more functionalities by installing Kong Plugins.

<script type="text/javascript" src="https://asciinema.org/a/16961.js" id="asciicast-16961" async data-speed="2"></script>

# Installing the Authentication Plugin

In this screencast we'll learn how to install a plugin on top of an API, specifically the Authentication Plugin.

The Authentication Plugin protects the API and requires the clients to send authentication credentials to authenticate themselves, otherwise the request won't go through.

Here we'll cover the details of installing the Plugin, while in the next screencast you can learn how to provision credentials for the API users.

<script type="text/javascript" src="https://asciinema.org/a/16980.js" id="asciicast-16980" async data-speed="2"></script>

# Creating an Account and an Application

This screencast shows how to create Accounts and Applications to consume an API that has been protected with the Authentication Plugin.

The Authentication Plugin in the example has been configured to support Query authentication (api-key authentication) looking for credentials in a field called `apikey`, that can be either sent in the querystring or as body parameter along with the request.

<script type="text/javascript" src="https://asciinema.org/a/16981.js" id="asciicast-16981" async data-speed="2"></script>
