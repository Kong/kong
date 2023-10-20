# Kong Runner Scripts

> In case of emergency break glass

These lua scripts are a set of basic tools designed to be used while troubleshooting Kong.

| Script         | Current Feature(s)                                                                                                          | Use                                                                                             | TODO                               |
|----------------|-----------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|------------------------------------|
| pg.lua         | * Test connectivity to Postgres database <br> * Runs a simple query once connected to retrieve the service list (arbitrary) | kong runner /usr/local/kong/scripts/pg.lua \<host\> \<port\> \<db\> \<user\> \<password\>       | Add TLS support                    |
| redis.lua      | * Tests connectivity to Redis <br> * Writes a key and reads back the value                                                  | kong runner /usr/local/kong/scripts/redis.lua \<host\> \<port\> \<password\> \<ssl\> \<verify\> | Add cluster/sentinel support       |
| tcp_socket.lua | * Test TCP port availability. Generally use to test server port availability connecting from Kong                           | kong runner /usr/local/kong/scripts/tcp_socket.lua \<host\> \<port\>                            | TBC                                |

## Invocation

```bash
$ kong runner /usr/local/kong/scripts/tcp_socket.lua google.com 443
Successfully connected to google.com:443!
```
