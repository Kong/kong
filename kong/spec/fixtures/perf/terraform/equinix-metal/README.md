Perf test terraform driver expects:
- `id_rsa` as the private key present
- `kong-ip`, `kong-internal-ip`, `worker-ip` and `worker-internal-ip`
to present in terraform output. If instance has no private IP,
use `<type>-ip` as `<type>-internal-ip` is also accepted.  
