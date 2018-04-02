# kong-plugin-enterprise-serverless

Kong Plugins for running Serverless functions in LUA.

## Plugins

Serverless is comprised of two plugins, each plugin runs at a different location in the plugin run-loop of Kong:

- `pre-function`
  - Runs before other plugins are ran.
- `post-function`
  - Runs after all other plugins have ran.

## Configuration

To configure Serverless Plugins you will need an API or Route / Service, then you will be able to configure the Serverless Plugin with your functions:

```bash
$ curl -X POST http://kong:8001/apis/{api}/plugins \
    --data "name=pre-function" \
    --data "config.functions[]=ngx.say('Hello World');ngx.exit(200)"
```

**Note**

`api` (required): The `id` or `name` of the API that this plugin configuration will target.

**Options**

| form parameter | default | description |
| --- | --- | --- |
| `name` | `pre-function` or `post-function` | The name of the plugin to use, in this case: `pre-function` |
| `config.functions` |  | List of one or more lua functions that will be interpreted and ran at run-time, interpreted functions  are then cached for later use. |

## Usage

XXX

## Enterprise Support

Support, Demo, Training, API Certifications and Consulting
available at https://getkong.org/enterprise.
