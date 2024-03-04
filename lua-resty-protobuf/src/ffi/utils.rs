use std::{cmp::min, ffi};

pub fn write_error_buffer(err_buf: *mut ffi::c_uchar, err_buf_len: ffi::c_uint, err_msg: &String) {
    if err_buf_len as usize == 0 {
        return;
    }

    let len = min((err_buf_len as usize) - 1, err_msg.len());
    unsafe {
        std::ptr::copy_nonoverlapping(err_msg.as_ptr(), err_buf, len);
        *err_buf.add(len) = 0;
    }
}
