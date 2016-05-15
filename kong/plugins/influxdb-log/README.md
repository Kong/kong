# influxdb

[Website](https://www.influxdata.com) |
[Docs](https://docs.influxdata.com/influxdb/v1.0/) |
[Installation](https://docs.influxdata.com/influxdb/v1.0/introduction/installation/)

## influxdb Initialize
If you’ve installed InfluxDB locally, the **influx** command should be available via the command line. Executing **influx** will start the CLI and automatically connect to the local InfluxDB instance (assuming you have already started the server with **service influxdb start** or by running **influxd** directly).

```
$ influx
Connected to http://localhost:8086 version 0.13.x
InfluxDB shell 0.13.x
>
> CREATE DATABASE kongdb
>
> SHOW DATABASES
name: databases
---------------
name
_internal
kongdb

>

```

now，influxdb is ok !

# influxdb-log

influxdb-log send request and response logs to an influxdb server.

## influxdb-log config


| parameter | required | default | type |sample
| --------- |:--------:| -------:|:----:|------
| http_endpoint | true | N/A | url | http://localhost:8086/write?db=kongdb
| method | false | POST | enum
| content_type | false | application/x-www-form-urlencoded | enum
| timeout | false | 10000 | number
| keepalive | false | 60000 | number

## Configuration
Configuring the plugin is straightforward, you can add it on top of an API (or Consumer) by executing the following request on your Kong server:

```
curl -X POST http://172.28.32.101:8001/plugins  \
  --data "name=influxdb-db" \
  --data "config.http_endpoint=http://172.28.32.101:8086/write?db=kongdb"
```
