const c_cast = @import("std").meta.cast;

const os_tag = @import("std").builtin.os.tag;
pub usingnamespace @cImport({
    @cInclude("stdlib.h");
    @cInclude("fcntl.h");
    @cInclude("locale.h");
    @cInclude("errno.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
    @cInclude("signal.h");
    @cInclude("sys/select.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/Xlib.h");
    @cInclude("X11/cursorfont.h");
    @cInclude("X11/keysym.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("X11/XKBlib.h");
    switch (os_tag) {
        .linux => @cInclude("pty.h"),
        .openbsd, .netbsd => @cInclude("util.h"),
        .freebsd, .dragonfly => @cInclude("libutil.h"),
        else => if (os_tag.isDarwin()) @cInclude("util.h"),
    }
});

pub inline fn _DisplayWidth(dpy: *Display, scr: c_int) c_int {
    return _ScreenOfDisplay(dpy, scr).*.width;
}
pub inline fn _DisplayHeight(dpy: *Display, scr: c_int) c_int {
    return _ScreenOfDisplay(dpy, scr).*.height;
}
pub inline fn _DefaultDepth(dpy: *Display, scr: c_int) c_int {
    return _ScreenOfDisplay(dpy, scr).*.root_depth;
}
pub inline fn _ScreenOfDisplay(dpy: *Display, scr: c_int) *Screen {
    return @ptrCast(*Screen, &c_cast(_XPrivDisplay, dpy).*.screens[@intCast(usize, scr)]);
}

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
