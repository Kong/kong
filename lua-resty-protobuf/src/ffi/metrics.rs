use bytes::BytesMut;

use crate::Metrics;
use std::ffi;

use super::utils::write_error_buffer;

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_metrics_new() -> *mut Metrics {
    Box::into_raw(Box::new(Metrics::new()))
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_metrics_get_serialized(
    metrics: *mut Metrics,
    buf: *mut ffi::c_uchar,
    buf_len: ffi::c_uint,
) -> ffi::c_uint {
    let metrics = unsafe { Box::from_raw(metrics) };
    let mut serialized = BytesMut::with_capacity(buf_len as usize);
    metrics.get_serialized(&mut serialized);

    let expected_len = serialized.len();
    if expected_len > buf_len as usize {
        return 0;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(serialized.as_ptr(), buf, expected_len);
    }

    expected_len as ffi::c_uint
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_metrics_add_gauge(
    metrics: *mut Metrics,
    name: *const ffi::c_char,
    name_len: ffi::c_uint,
    value: ffi::c_longlong,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let metrics = unsafe { &mut *metrics };
    let name = unsafe { std::slice::from_raw_parts(name as *const u8, name_len as usize) };
    let name = std::str::from_utf8(name);

    if let Err(e) = name {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `name` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    metrics.add_int64_gauge(name.unwrap(), value);

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_metrics_add_sum(
    metrics: *mut Metrics,
    name: *const ffi::c_char,
    name_len: ffi::c_uint,
    value: ffi::c_longlong,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let metrics = unsafe { &mut *metrics };
    let name = unsafe { std::slice::from_raw_parts(name as *const u8, name_len as usize) };
    let name = std::str::from_utf8(name);

    if let Err(e) = name {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `name` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    metrics.add_int64_sum(name.unwrap(), value);

    0
}
