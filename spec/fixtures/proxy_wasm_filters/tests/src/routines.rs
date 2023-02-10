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
        ctx.set_http_request_header(HEADER_NAME, None)
    }
}
