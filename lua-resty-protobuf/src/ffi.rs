use std::ffi;

use crate::Trace;
use std::cmp::min;

fn write_error_buffer(err_buf: *mut ffi::c_uchar, err_buf_len: ffi::c_uint, err_msg: &String) {
    if err_buf_len as usize == 0 {
        return;
    }

    let len = min((err_buf_len as usize) - 1, err_msg.len());
    unsafe {
        std::ptr::copy_nonoverlapping(err_msg.as_ptr(), err_buf, len);
        *err_buf.add(len) = 0;
    }
}

#[no_mangle]
pub unsafe extern "C" fn lua_resty_protobuf_trace_new() -> *mut ffi::c_void {
    Box::into_raw(Box::new(Trace::new())) as *mut ffi::c_void
}

#[no_mangle]
pub unsafe extern "C" fn lua_resty_protobuf_trace_free(trace: *mut ffi::c_void) {
    let trace = unsafe { Box::from_raw(trace as *mut Trace) };
    trace.send_to_udp();

    // drop it explicitly to make the logic more clear
    drop(trace);
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_get_serialized(
    trace: *mut ffi::c_void,
    buf: *mut ffi::c_uchar,
    buf_len: ffi::c_uint,
) -> ffi::c_uint {
    let trace = unsafe { &*(trace as *mut Trace) };
    let serialized = trace.get_serialized();

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
    trace: *mut ffi::c_void,
    name: *const ffi::c_char,
    name_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *(trace as *mut Trace) };
    let name = unsafe { std::slice::from_raw_parts(name as *const u8, name_len as usize) };
    let name = std::str::from_utf8(name);

    if let Err(name) = name {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `name` is not a valid utf-8 string: ");
        err_msg.push_str(name.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    trace.enter_span(name.unwrap());

    return 0;
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_exit_span(trace: *mut ffi::c_void) {
    let trace = unsafe { &mut *(trace as *mut Trace) };
    trace.exit_span();
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_string_attribute(
    trace: *mut ffi::c_void,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: *const ffi::c_char,
    value_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *(trace as *mut Trace) };
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

    trace.add_string_attribute(key.unwrap(), value.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_trace_add_bool_attribute(
    trace: *mut ffi::c_void,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_int,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *(trace as *mut Trace) };
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
    trace: *mut ffi::c_void,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_longlong,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *(trace as *mut Trace) };
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
    trace: *mut ffi::c_void,
    key: *const ffi::c_char,
    key_len: ffi::c_uint,
    value: ffi::c_double,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let trace = unsafe { &mut *(trace as *mut Trace) };
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
