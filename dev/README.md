# Development Environment using Vagrant
Vagrant is used to create an isolated development environment. 

## Starting the environment
Once you have Vagrant installed execute the following command from this directory:
```
vagrant up
```

The startup process will install all the dependencies necessary for developing. The kong source code is mounted at `/kong`. The host ports `8000` and `8001` will be forwarded to the Vagrant box.

## Building Kong
To build kong execute the following commands:

1. From the host machine SSH into the Vagrant box: `vagrant ssh`
2. Change to the root of the kong source code: `cd /kong`
3. Make kong: `sudo make dev`

## Running Kong
While on SSHed into the Vagrant box, start Kong with the following commands:
1. Change to the root of the kong source code: `cd /kong`
2. Start kong `kong start -c kong_DEVELOPMENT.yml`

## Testing Kong
To verify Kong is running successfully, from the host machine execute the following command from the commandline:
```
curl http://localhost:8001
```

You should receive a JSON response:
```
{
  "version": "0.4.0",
  "lua_version": "LuaJIT 2.1.0-alpha",
  "tagline": "Welcome to Kong",
  "hostname": "precise64",
  "plugins": {
    "enabled_in_cluster": {},
    "available_on_server": [
      "ssl",
      "keyauth",
      "basicauth",
      "oauth2",
      "ratelimiting",
      "tcplog",
      "udplog",
      "filelog",
      "httplog",
      "cors",
      "request_transformer",
      "response_transformer",
      "requestsizelimiting",
      "analytics",
      "ip-restriction"
    ]
  }
}
```