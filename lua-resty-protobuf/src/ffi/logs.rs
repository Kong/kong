use bytes::BytesMut;

use crate::Logs;
use std::ffi;

use super::utils::write_error_buffer;

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_logs_new() -> *mut Logs {
    Box::into_raw(Box::new(Logs::new()))
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_logs_get_serialized(
    logs: *mut Logs,
    buf: *mut ffi::c_uchar,
    buf_len: ffi::c_uint,
) -> ffi::c_uint {
    let logs = unsafe { Box::from_raw(logs) };
    let mut serialized = BytesMut::with_capacity(buf_len as usize);
    logs.get_serialized(&mut serialized);

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
pub extern "C" fn lua_resty_protobuf_logs_add_info(
    logs: *mut Logs,
    time_unix_nano: ffi::c_ulonglong,
    message: *const ffi::c_char,
    message_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let logs = unsafe { &mut *logs };
    let message = unsafe { std::slice::from_raw_parts(message as *const u8, message_len as usize) };
    let message = std::str::from_utf8(message);

    if let Err(e) = message {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `message` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    logs.add_info_log(time_unix_nano, message.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_logs_add_warn(
    logs: *mut Logs,
    time_unix_nano: ffi::c_ulonglong,
    message: *const ffi::c_char,
    message_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let logs = unsafe { &mut *logs };
    let message = unsafe { std::slice::from_raw_parts(message as *const u8, message_len as usize) };
    let message = std::str::from_utf8(message);

    if let Err(e) = message {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `message` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    logs.add_warning_log(time_unix_nano, message.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_logs_add_error(
    logs: *mut Logs,
    time_unix_nano: ffi::c_ulonglong,
    message: *const ffi::c_char,
    message_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let logs = unsafe { &mut *logs };
    let message = unsafe { std::slice::from_raw_parts(message as *const u8, message_len as usize) };
    let message = std::str::from_utf8(message);

    if let Err(e) = message {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `message` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    logs.add_error_log(time_unix_nano, message.unwrap());

    0
}

#[no_mangle]
pub extern "C" fn lua_resty_protobuf_logs_add_fatal(
    logs: *mut Logs,
    time_unix_nano: ffi::c_ulonglong,
    message: *const ffi::c_char,
    message_len: ffi::c_uint,
    err_buf: *mut ffi::c_uchar,
    err_buf_len: ffi::c_uint,
) -> ffi::c_int {
    let logs = unsafe { &mut *logs };
    let message = unsafe { std::slice::from_raw_parts(message as *const u8, message_len as usize) };
    let message = std::str::from_utf8(message);

    if let Err(e) = message {
        let mut err_msg = String::new();
        err_msg.push_str("arguement `message` is not a valid utf-8 string: ");
        err_msg.push_str(e.to_string().as_str());
        write_error_buffer(err_buf, err_buf_len, &err_msg);

        return 1;
    }

    logs.add_fatal_log(time_unix_nano, message.unwrap());

    0
}
