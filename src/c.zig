pub const wchar_t = c_int;
pub usingnamespace @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/types.h");
    @cInclude("pwd.h");
    @cInclude("unistd.h");
    @cInclude("limits.h");
    @cInclude("termios.h");
    @cInclude("pty.h");
});

// wctype.h
pub extern "c" fn wcwidth(c: wchar_t) c_int;
pub extern "c" fn wcschr(s: [*:0]const wchar_t, c: wchar_t) ?*wchar_t;
// stdlib.h
pub extern "c" fn strtol(s: [*:0]const u8, end: ?*[*]const u8, base: c_int) c_long;
pub extern "c" fn atoi(s: [*:0]const u8) c_int;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
pub extern "c" fn system(cmd: [*:0]const u8) c_int;
// ctype.h
pub extern "c" fn isprint(c: c_int) c_int;
// string.h
pub extern "c" fn strerror(errnum: c_int) [*:0]u8;

// signal.h
// pub extern "c" fn signal(sig: c_int, func: ?fn (c_int) void) ?fn (c_int) void;

pub inline fn _FD_MASK(fd: c_int) __fd_mask {
    return @as(__fd_mask, 1) << @intCast(u6, @mod(fd, __NFDBITS));
}
pub inline fn _FD_ELT(fd: c_int) usize {
    return @intCast(usize, @divTrunc(fd, __NFDBITS));
}
pub inline fn _FD_ZERO(fdset: *fd_set) void {
    var __arr = fdset;
    var __i: u32 = 0;
    while (__i < @sizeOf(fd_set) / @sizeOf(__fd_mask)) : (__i += 1) {
        __FDS_BITS(__arr)[__i] = 0;
    }
}
pub inline fn _FD_SET(fd: anytype, fdset: *fd_set) void {
    __FDS_BITS(fdset)[_FD_ELT(fd)] |= _FD_MASK(fd);
}
pub inline fn _FD_CLR(fd: anytype, fdset: *fd_set) void {
    __FDS_BITS(fdset)[_FD_ELT(fd)] &= ~_FD_MASK(fd);
}
pub inline fn _FD_ISSET(fd: anytype, fdset: *fd_set) bool {
    return (__FDS_BITS(fdset)[_FD_ELT(fd)] & _FD_MASK(fd)) != 0;
}
