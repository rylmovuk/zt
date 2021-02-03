const Bitset = @import("util.zig").Bitset;
const st = @import("st.zig");
const Glyph = st.Glyph;
const Line = st.Line;

pub const WindowMode = Bitset(enum {
    Visible,
    Focused,
    AppKeypad,
    MouseButton,
    MouseMotion,
    Reverse,
    KeyboardLock,
    Hide,
    AppCursor,
    MouseSGR,
    @"8Bit",
    Blink,
    FBlink,
    Focus,
    MouseX10,
    MouseMany,
    BrcktPaste,
    Numlock,
});
pub const winmode_mouse = WindowMode.init_with(.{ .MouseButton, .MouseMotion, .MouseX10, .MouseMany });

const external = struct {
    pub extern fn xbell() void;
    pub extern fn xclipcopy() void;
    pub extern fn xdrawcursor(x: c_int, y: c_int, g: Glyph, ox: c_int, oy: c_int, og: Glyph) void;
    pub extern fn xdrawline(line: Line, x1: c_int, y1: c_int, x2: c_int) void;
    pub extern fn xfinishdraw() void;
    pub extern fn xloadcols() void;
    pub extern fn xsetcolorname(i: c_int, s: ?[*:0]const u8) c_int;
    pub extern fn xsettitle(s: [*:0]u8) void;
    pub extern fn xsetcursor(c: c_int) c_int;
    pub extern fn xsetmode(b: c_int, mode: c_uint) void;
    pub extern fn xsetpointermotion(b: c_int) void;
    pub extern fn xsetsel(s: [*:0]const u8) void;
    pub extern fn xstartdraw() c_int;
    pub extern fn xximspot(x: c_int, y: c_int) void;
};

pub const xbell = external.xbell;
pub const xclipcopy = external.xclipcopy;
pub fn xdrawcursor(x: u32, y: u32, g: Glyph, ox: u32, oy: u32, og: Glyph) void {
    external.xdrawcursor(@intCast(c_int, x), @intCast(c_int, y), g, @intCast(c_int, ox), @intCast(c_int, oy), og);
}
pub fn xdrawline(line: Line, x1: u32, y1: u32, x2: u32) void {
    external.xdrawline(line, @intCast(c_int, x1), @intCast(c_int, y1), @intCast(c_int, x2));
}
pub const xfinishdraw = external.xfinishdraw;
pub const xloadcols = external.xloadcols;
pub fn xsetcolorname(i: i32, s: ?[*:0]const u8) bool {
    return external.xsetcolorname(@intCast(c_int, i), s) != 0;
}
pub const xsettitle = external.xsettitle;
pub fn xsetcursor(c: u32) bool {
    // thanks for breaking the convention, authors of st
    return external.xsetcursor(@intCast(c_int, c)) == 0;
}
pub fn xsetmode(b: bool, mode: WindowMode) void {
    external.xsetmode(@boolToInt(b), mode.bits);
}
pub fn xsetpointermotion(b: bool) void {
    external.xsetpointermotion(@boolToInt(b));
}
pub const xsetsel = external.xsetsel;
pub fn xstartdraw() bool {
    return external.xstartdraw() != 0;
}
pub fn xximspot(x: u32, y: u32) void {
    external.xximspot(@intCast(c_int, x), @intCast(c_int, y));
}
