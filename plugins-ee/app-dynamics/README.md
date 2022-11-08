# Kong Plugin for AppDynamics

The goal of this plugin is to capture entry and exit points such that
the Kong gateway appears on the AppDynamics controller flow maps and
is able to detect incoming transactions and backend calls.

This provides customers with E2E business transactions by
identifying/passing a correlation header through Kong, to provide
performance metrics (load, response time, errors) via the AppDynamics
controller.

## Plugin Design

![Plugin Design](image/verifone-AppD%20plugin%20arch.png)

**Plugin Design consideration**
- This plugin is architecturally flexible to either initiate a
  business transaction when Kong is the first entry point or
  participate in existing business transition when Kong is serving
  traffic for internal API calls.
- Kong route name used to mark as Business transaction and Kong
  service to used to mark as backed service to depict the right
  component in AppDynamics Flow map.

**Native Lua FFI**
- Performant and native way to call C based interface
- AppDynamics C Agent running on the same node as kong data plane

## Sample AppDynamics Flow Map

**AppDynamics Flow Map**
![AppDynamics Flow Map](image/Kong-AppD-plugin%20in%20Action.png)

**AppDynamics Business Transaction View**
![AppDynamics BT](image/kong-appd-bt-view.png)

**AppDynamics Business Transaction Detailed View**
![AppDynamics BT detailed](image/kong-appd-bt-detailed.png)

# Platform support

The AppDynamics C SDK supports Linux distributions based on glibc
2.5+.  MUSL based distributions like the Alpine distribution, which is
popular for container usage, are not supported.  Kong Gateway must
thus be running on a glibc based distribution like RHEL, CentOS,
Debian or Ubuntu to support this plugin.  See the
[AppDynamics C/C++ SDK Supported Environments](https://docs.appdynamics.com/appd/21.x/21.12/en/application-monitoring/install-app-server-agents/c-c++-sdk/c-c++-sdk-supported-environments)
document for more information.

# Installation

To use the AppDynamics plugin in Kong Gateway, the AppDynamics C/C++
SDK must be installed on all nodes running Kong Gateway.  The SDK is
not distributed with Kong Gateway due to licensing restrictions.  It
must be downloaded from the
[AppDynamics Download Portal](https://download.appdynamics.com/download/).
The only file needed by the plugin is the **libappdynamics.so** shared
library file.  It must be placed in one of the locations configured by
the
[system's shared library loader](https://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html).
Alternatively, the **LD_LIBRARY_PATH** environment variable can be set
to the directory containing the **libappdynamics.so** file when
starting Kong Gateway.

If the AppDynamics plugin is enabled in the configuration, Kong
Gateway will refuse to start if the **libappdynamics.so** file cannot
be loaded.  The error message will be similar to this:

```kong/plugins/app-dynamics/appdynamics.lua:74: libappdynamics.so: cannot open shared object file: No such file or directory```

# Configuration

The AppDynamics plugin is configured through environment variables
that need to be set when Kong Gateway is started.  The environment
variables used by the plugin are shown in the table below.  Note that
if an environment variable has no default, it must be set for the
plugin to operate correctly.

The AppDynamics plugin makes use of the AppDynamics C/C++ SDK to send
information to the AppDynamics controller.  Please refer to the
[AppDynamics C/C++ SDK documentation](https://docs.appdynamics.com/appd/21.x/21.12/en/application-monitoring/install-app-server-agents/c-c++-sdk/use-the-c-c++-sdk)
to get further information on the configuration parameters.

## Environment variables

| Name | Description | Type | Default |
|--|--|--|--|
| KONG_APPD_CONTROLLER_HOST | Hostname of the AppDynamics controller | String | |
| KONG_APPD_CONTROLLER_PORT | Port number to use to communicate with controller | NUMBER | 443 |
| KONG_APPD_CONTROLLER_ACCOUNT | Account name to use on controller | String | |
| KONG_APPD_CONTROLLER_ACCESS_KEY | Access key to use on the AppDynamics controller | String |
| KONG_APPD_LOGGING_LEVEL | Logging level of the AppDynamics SDK Agent | NUMBER | 2 |
| KONG_APPD_LOGGING_LOG_DIR | Directory into which agent log files are written | STRING | "/tmp/appd" |
| KONG_APPD_TIER_NAME | Tier name to use in business transactions | String | |
| KONG_APPD_APP_NAME | Application name to report to AppDynamics | STRING | "Kong" |
| KONG_APPD_NODE_NAME | Node name to report to AppDynamics | STRING | System hostname |
| KONG_APPD_INIT_TIMEOUT_MS | Maximum time to wait for a controller connection when starting | NUMBER | 5000 |
| KONG_APPD_CONTROLLER_USE_SSL | Use SSL encryption in controller communication | BOOLEAN | "on" |
| KONG_APPD_CONTROLLER_HTTP_PROXY_HOST | Hostname of proxy to use to communicate with controller | STRING | "" |
| KONG_APPD_CONTROLLER_HTTP_PROXY_PORT | Port number of controller proxy | NUMBER | 0 |
| KONG_APPD_CONTROLLER_HTTP_PROXY_USERNAME | Username to use to identify to proxy | SECRET_STRING | "" |
| KONG_APPD_CONTROLLER_HTTP_PROXY_PASSWORD | Password to use to identify to proxy | SECRET_STRING | "" |

### Possible values for the `KONG_APPD_LOGGING_LEVEL` parameter

The `KONG_APPD_LOGGING_LEVEL` environment variable can be set to
define the minimum log level.  It needs to be specified as a numeric
value with the following meanings:

| Value | Name | Description |
|--|--|--|
| 0 | TRACE | Detailed trace-level information |
| 1 | DEBUG | Debugging messages |
| 2 | INFO | Informational messages (low volume) |
| 3 | WARN | Warnings that permit the agent to operate, but should be looked into |
| 4 | ERROR | Errors, could indicate data loss |
| 5 | FATAL | Fatal errors that prevent the agent from operating |

# Agent logging

The AppDynamics agent logs information into separate log files that it
manages on its own and that are independent of the logs of Kong
Gateway.  By default, log files are written to the `/tmp/appd`
directory.  This location can be changed according to local policies
by setting the `KONG_APPD_LOGGING_LOG_DIR` environment variable.

When problems occur with the AppDynamics integration, make sure that
you inspect the AppDynamics agent's log files in addition to the Kong
Gateway logs.

# AppDynamics node name considerations

The AppDynamics plugin defaults the `KONG_APPD_NODE_NAME` to the local
host name, which typically reflects the container ID in containerized
applications.  As multiple instances of the AppDynamics agent must use
different node names and one agent exists for each of Kong Gateway's
worker processes, the node name is suffixed by the worker ID.  This
results in multiple nodes to be created for each Kong Gateway
instance, one for each worker process.
