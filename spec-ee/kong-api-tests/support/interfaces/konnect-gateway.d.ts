export interface GatewayService {
  name: string;
  client_certificate?: string | null;
  connect_timeout?: number;
  enabled?: boolean;
  host?: string;
  path?: string;
  port?: number;
  protocol?: string;
  read_timeout?: number;
  retries?: number;
  tags?: Array<string>;
  write_timeout?: number;
}

export interface GatewayRoute {
  service: { id: string };
  destinations?: string | null;
  headers?: string | null;
  hosts?: string | null;
  https_redirect_status_code?: number;
  methods?: Array<string>;
  name?: string;
  paths?: Array<string>;
  path_handling?: string;
  preserve_host?: boolean;
  protocols?: Array<string>;
  regex_priority?: number;
  snis?: string | null;
  sources?: string | null;
  strip_path?: boolean;
  tags?: Array<string>;
}

export interface KokoAuthHeaders {
  [key: string]: AxiosHeaderValue;
}