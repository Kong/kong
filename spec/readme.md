Test helpers for Kong (integration) tests
=========================================

To generate the documentation run the following command in the Kong source tree:

```
# install ldoc using LuaRocks
luarocks install ldoc

# generate and open the docs
cd spec && ldoc . && open docs/index.html && cd ..
```

## Environment variables

When testing Kong will ingore the `KONG_xxx` environment variables that are
usually used to configure it. This is to make sure the tests run deterministic.
If for some reason this behaviour needs to be overridden, then the `KONG_TEST_xxx`
version of the variable can be used, that will be respected by the Kong test
instance.

To prevent the test helpers from cleaning the Kong working directory, the
variable `KONG_TEST_DONT_CLEAN` can be set.
This comes in handy when inspecting then logs after the tests completed.

When testing with Redis, the environment variable `KONG_SPEC_REDIS_HOST` can be
used to specify where the Redis server can be found. If not specified it will default
to `127.0.0.1`. This setting is available to tests via `helpers.redis_host`.

The configuration file to use can be set by `KONG_SPEC_TEST_CONF_PATH`. It can be
gotten from the helpers as field `helpers.test_conf_path`.
