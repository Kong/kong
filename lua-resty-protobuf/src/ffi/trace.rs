use bytes::BytesMut;

use crate::Traces;
use std::ffi;

use super::utils::write_error_buffer;

#[no_mangle]
pub unsafe extern "C" fn lua_resty_protobuf_trace_new() -> *mut Traces {
    Box::into_raw(Box::new(Traces::new()))
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_get_serialized(
    traces: *mut Traces,
    buf: *mut ffi::c_uchar,
    buf_len: ffi::c_uint,
) -> ffi::c_uint {
    let traces = unsafe { Box::from_raw(traces) };
    let mut serialized = BytesMut::with_capacity(buf_len as usize);
    traces.get_serialized(&mut serialized);

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
pub extern "C" fn lua_resty_protobuf_trace_enter_span(
    traces: *mut Traces,
    name: *const ffi::c_char,
    name_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let traces = unsafe { &mut *traces };
    let name = unsafe { std::slice::from_raw_parts(name as *const u8, name_len as usize) };
    let name = std::str::from_utf8(name);

    if let Err(e) = name {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `name` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    traces.enter_span(name.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_exit_span(traces: *mut Traces) {
    let traces = unsafe { &mut *traces };
    traces.exit_span();
}


#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_string_attribute(
    traces: *mut Traces,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: *const ffi::c_char,
    value_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let traces = unsafe { &mut *traces };
    let key = unsafe { std::slice::from_raw_parts(key as *const u8, key_len as usize) };
    let key = std::str::from_utf8(key);

    if let Err(e) = key {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `key` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    let value = unsafe { std::slice::from_raw_parts(value as *const u8, value_len as usize) };
    let value = std::str::from_utf8(value);

    if let Err(e) = value {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `value` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    traces.add_string_attribute(key.unwrap(), value.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_bool_attribute(
    traces: *mut Traces,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_int,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *traces };
    let key = unsafe { std::slice::from_raw_parts(key as *const u8, key_len as usize) };
    let key = std::str::from_utf8(key);

    if let Err(e) = key {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `key` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    trace.add_bool_attribute(key.unwrap(), value != 0);

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_int64_attribute(
    traces: *mut Traces,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_longlong,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *traces };
    let key = unsafe { std::slice::from_raw_parts(key as *const u8, key_len as usize) };
    let key = std::str::from_utf8(key);

    if let Err(e) = key {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `key` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    trace.add_int64_attribute(key.unwrap(), value);

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_double_attribute(
    traces: *mut Traces,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_double,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *traces };
    let key = unsafe { std::slice::from_raw_parts(key as *const u8, key_len as usize) };
    let key = std::str::from_utf8(key);

    if let Err(e) = key {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `key` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    trace.add_double_attribute(key.unwrap(), value);

    0
}
