export interface PollyConfig {
  adapters?: string[];
  adapterOptions?: {
    fetch?: {
      context?: any;
    };
    xhr?: {
      context?: any;
    };
    [key: string]: any;
  };
  persister?: string;
  persisterOptions?: {
    fs?: {
      recordingsDir?: string;
    };
    [key: string]: any;
  };
  logging?: boolean;
  logLevel?: 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'silent';
  mode?: 'record' | 'replay' | 'passthrough';
  expiresIn?: string;
  expiryStrategy?: 'warn' | 'error' | 'record';
  timing?: {
    connect?: number | (() => number);
    response?: number | (() => number);
  };
  matchRequestsBy?: {
    method?: boolean;
    url?: {
      protocol?: boolean;
      username?: boolean;
      password?: boolean;
      host?: boolean;
      hostname?: boolean;
      port?: boolean;
      pathname?: boolean;
      query?: boolean | string[];
      hash?: boolean;
    };
    headers?: boolean | string[];
    body?: boolean;
  };
  recordIfMissing?: boolean;
  flushRequestsOnStop?: boolean;
  requestDelay?: number;
  recordFailedRequests?: boolean;
}