pub const wchar_t = c_int;
pub usingnamespace @cImport({
    @cInclude("stdio.h");
});

// wctype.h
pub extern "c" fn wcwidth(c: wchar_t) c_int;
pub extern "c" fn wcschr(s: [*:0]const wchar_t, c: wchar_t) ?*wchar_t;
// stdlib.h
pub extern "c" fn strtol(s: [*:0]const u8, end: ?*[*]const u8, base: c_int) c_long;
pub extern "c" fn atoi(s: [*:0]const u8) c_int;
// ctype.h
pub extern "c" fn isprint(c: c_int) c_int;
