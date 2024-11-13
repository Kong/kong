use crate::*;

pub(crate) fn add_request_header(ctx: &mut TestHttp) {
    const HEADER_NAME: &str = "X-PW-Add-Header";

    if let Some(header) = ctx.get_http_request_header(HEADER_NAME) {
        let (name, value) = header.split_once('=').unwrap();

        ctx.add_http_request_header(name, value);
        ctx.set_http_request_header(HEADER_NAME, None)
    }
}

pub(crate) fn add_response_header(ctx: &mut TestHttp) {
    const HEADER_NAME: &str = "X-PW-Add-Resp-Header";

    if let Some(header) = ctx.get_http_request_header(HEADER_NAME) {
        let (name, value) = header.split_once('=').unwrap();

        ctx.add_http_response_header(name, value);
    }

    const CONFIG_HEADER_NAME: &str = "X-PW-Resp-Header-From-Config";
    if let Some(config) = &ctx.config {
        info!("[proxy-wasm] setting {:?} header from config", CONFIG_HEADER_NAME);
        if let Some(value) = config.map.get("add_resp_header") {
            ctx.add_http_response_header(CONFIG_HEADER_NAME, value);
        }
    }
}
