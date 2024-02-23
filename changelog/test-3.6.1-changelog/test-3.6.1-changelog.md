## Kong


### Performance
#### Plugin

- **Opentelemetry**: increase queue max batch size to 200
 [#12542](https://github.com/Kong/kong/issues/12542)
 [KAG-3173](https://konghq.atlassian.net/browse/KAG-3173)




### Features
#### Configuration

- now TLSv1.1 and lower is by default disabled in OpenSSL 3.x
 [#12556](https://github.com/Kong/kong/issues/12556)
 [KAG-3259](https://konghq.atlassian.net/browse/KAG-3259)

### Fixes
#### Default

- Fix a bug where the ulimit setting (open files) is low Kong will fail to start as the lua-resty-timer-ng exhausts the available worker_connections. Decrease the concurrency range of the lua-resty-timer-ng library from [512, 2048] to [256, 1024] to fix this bug.
 [#12608](https://github.com/Kong/kong/issues/12608)
 [KAG-3779](https://konghq.atlassian.net/browse/KAG-3779) [FTI-5780](https://konghq.atlassian.net/browse/FTI-5780)
## Kong-Manager







