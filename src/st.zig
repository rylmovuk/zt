const std = @import("std");
const os = std.os;
const c = @import("c.zig");
const main = @import("main.zig");
const cfg = @import("config.zig");

const Bitset = @import("util.zig").Bitset;

pub inline fn divceil(n: anytype, d: @TypeOf(n)) @TypeOf(n) {
    return @divTrunc(n + (d - 1), d);
}

pub inline fn ATTRCMP(a: Glyph, b: Glyph) bool {
    return a.mode.bits != b.mode.bits or a.fg != b.fg or a.bg != b.bg;
}

pub inline fn MODBIT(x: anytype, set: bool, bit: @typeInfo(@TypeOf(x)).Pointer.child) void {
    if (set) x.* |= bit else x.* &= ~bit;
}
// pub inline fn TIMEDIFF(t1: c.struct_timespec, t2: c.struct_timespec) c_long {
//     return (t1.tv_sec - t2.tv_sec) * 1000 + @divTrunc(t1.tv_nsec - t2.tv_nsec, 1_000_000);
// }
pub inline fn TRUECOLOR(r: u32, g: u32, b: u32) u32 {
    return 1 << 24 | r << 16 | g << 8 | b;
}
pub inline fn IS_TRUECOL(x: u32) bool {
    return 1 << 24 & x != 0;
}

pub const Attr = Bitset(enum {
    Bold,
    Faint,
    Italic,
    Underline,
    Blink,
    Reverse,
    Invisible,
    Struck,
    Wrap,
    Wide,
    WDummy,
});
pub const attr_boldfaint = Attr.init_with(.{ .Bold, .Faint });

pub const Rune = u32;

pub const Glyph = extern struct {
    u: Rune = 0,
    mode: u16 = Attr.empty.bits,
    fg: u32,
    bg: u32,
};
fn as_attr(bits: u32) Attr {
    return .{ .bits = @truncate(Attr.Bits, bits) };
}

pub const Line = [*]Glyph;

pub const Arg = union {
    i: c_int,
    ui: c_uint,
    f: f64,
    v: ?*c_void,
    none: void,

    pub const None = &Arg{ .none = {} };
};

pub inline fn limit(x: anytype, low: @TypeOf(x), hi: @TypeOf(x)) @TypeOf(x) {
    return if (x < low) low else if (x > hi) hi else x;
}

// Arbitrary sizes
const utf_invalid = 0xFFFD;
const utf_size = 4;
const esc_buf_size = 128 * utf_size;
const esc_arg_size = 16;
const str_buf_size = esc_buf_size;
const str_arg_size = esc_arg_size;

// Macros
inline fn ISCONTROLC0(ch: Rune) bool {
    return (0 <= ch and ch <= 0x1f) or ch == 0o177;
}
inline fn ISCONTROLC1(ch: Rune) bool {
    return 0x80 <= ch and ch <= 0x9f;
}
inline fn ISCONTROL(ch: Rune) bool {
    return ISCONTROLC0(ch) or ISCONTROLC1(ch);
}
inline fn ISDELIM(u: Rune) bool {
    return u != 0 and c.wcschr(&cfg.worddelimiters, @intCast(c.wchar_t, u)) != null;
}

const external = struct {
    pub extern fn xmalloc(len: usize) *c_void;
    pub extern fn xrealloc(p: ?*c_void, len: usize) *c_void;
    pub extern fn ttywrite(s: [*]const u8, n: usize, may_echo: c_int) void;
    pub extern fn tprinter(s_ptr: [*]const u8, s_len: usize) void;
    pub extern fn resettitle() void;
};

const TermMode = Bitset(enum {
    Wrap,
    Insert,
    Altscreen,
    CrLf,
    Echo,
    Print,
    Utf8,
    Sixel,
});

const CURSOR_DEFAULT: u8 = 0;
const CURSOR_WRAPNEXT: u8 = 1;
const CURSOR_ORIGIN: u8 = 2;

const Charset = enum { Graphic0, Graphic1, Uk, Usa, Multi, Ger, Fin };

const Escape = Bitset(enum {
    Start,
    CSI,
    STR, // OSC, PM, APC
    AltCharset,
    StrEnd, // a final string was encountered
    Test, // Enter in test mode
    Utf8,
    DCS,
});

const utfbyte = [utf_size + 1]u8{ 0x80, 0, 0xC0, 0xE0, 0xF0 };
const utfmask = [utf_size + 1]u8{ 0xC0, 0x80, 0xE0, 0xF0, 0xF8 };
const utfmin = [utf_size + 1]Rune{ 0, 0, 0x80, 0x800, 0x10000 };
const utfmax = [utf_size + 1]Rune{ 0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF };

// instance
var sel = Selection{};
/// State related to the selection and functions to manipulate it
const Selection = struct {
    const Coords = struct { x: u32 = 0, y: u32 = 0 };
    const SelectionMode = enum { Idle, Empty, Ready };
    pub const SelectionType = enum(u2) { None = 0, Regular = 1, Rectangular = 2 };
    pub const SelectionSnap = enum(u2) { None = 0, SnapWord = 1, SnapLine = 2 };

    pub const no_sel = std.math.maxInt(u32);

    mode: SelectionMode = .Idle,
    @"type": SelectionType = .None,
    snap_kind: SelectionSnap = .None,
    /// normalized begin
    nb: Coords = .{},
    /// normalized end
    ne: Coords = .{},
    /// original begin
    /// ob.x is set to `no_sel` (`maxInt(u32)`) if there's no selection
    ob: Coords = .{},
    /// original end
    oe: Coords = .{},
    alt: bool = false,

    export fn selinit() void {
        sel.init();
    }
    pub fn init(self: *Selection) void {
        self.mode = .Idle;
        self.snap_kind = .None;
        self.ob.x = no_sel;
    }

    export fn selstart(col: c_int, row: c_int, snap_kind: c_int) void {
        sel.start(@intCast(u32, col), @intCast(u32, row), @intToEnum(SelectionSnap, @intCast(u2, snap_kind)));
    }
    pub fn start(self: *Selection, col: u32, row: u32, snap_kind: SelectionSnap) void {
        self.clear();
        self.mode = .Empty;
        self.@"type" = .Regular;
        self.alt = term.mode.get(.Altscreen);
        self.snap_kind = snap_kind;
        self.oe.x = col;
        self.ob.x = col;
        self.oe.y = row;
        self.ob.y = row;
        self.normalize();

        if (self.snap_kind != .None) self.mode = .Ready;
        term.setDirt(self.nb.y, self.ne.y);
    }

    export fn selextend(col: c_int, row: c_int, typ: c_int, done: c_int) void {
        sel.extend(@intCast(u32, col), @intCast(u32, row), @intToEnum(SelectionType, @intCast(u2, typ)), done != 0);
    }
    pub fn extend(self: *Selection, col: u32, row: u32, typ: SelectionType, done: bool) void {
        if (self.mode == .Idle) return;
        if (done and self.mode == .Empty) {
            self.clear();
            return;
        }

        const oldey = self.oe.y;
        const oldex = self.oe.x;
        const oldsby = self.nb.y;
        const oldsey = self.ne.y;
        const oldtype = self.@"type";

        self.oe.x = col;
        self.oe.y = row;
        self.normalize();
        self.@"type" = typ;

        if (oldey != self.oe.y or oldex != self.oe.x or oldtype != self.@"type" or self.mode == .Empty)
            term.setDirt(std.math.min(self.nb.y, oldsby), std.math.max(self.ne.y, oldsey));

        self.mode = if (done) .Idle else .Ready;
    }

    fn normalize(self: *Selection) void {
        if (self.@"type" == .Regular and self.ob.y != self.oe.y) {
            self.nb.x = if (self.ob.y < self.oe.y) self.ob.x else self.oe.x;
            self.ne.x = if (self.ob.y < self.oe.y) self.oe.x else self.ob.x;
        } else {
            self.nb.x = std.math.min(self.ob.x, self.oe.x);
            self.ne.x = std.math.max(self.ob.x, self.oe.x);
        }

        self.snap(&self.nb.x, &self.nb.y, -1);
        self.snap(&self.ne.x, &self.ne.y, 1);

        // expand selection over line breaks
        if (self.@"type" == .Rectangular)
            return;
        const i = term.lineLen(self.nb.y);
        if (i < self.nb.x)
            self.nb.x = i;
        if (term.lineLen(self.ne.y) <= self.ne.x)
            self.ne.x = term.col - 1;
    }

    export fn selected(x: c_int, y: c_int) c_int {
        return @boolToInt(sel.isSelected(@intCast(u32, x), @intCast(u32, y)));
    }
    pub fn isSelected(self: *const Selection, x: u32, y: u32) bool {
        if (self.mode == .Empty or self.ob.x == Selection.no_sel or self.alt != term.mode.get(.Altscreen))
            return false;

        if (self.@"type" == .Rectangular)
            return self.nb.y <= y and y <= self.ne.y;

        return (self.nb.y <= y and y <= self.ne.y) //
            and (y != self.nb.y or x >= self.nb.x) //
            and (y != self.ne.y or x <= self.ne.x);
    }

    /// direction must be either +1 or -1
    fn snap(self: *Selection, x: *u32, y: *u32, direction: i2) void {
        switch (self.snap_kind) {
            .SnapWord => {
                // Snap around if the word wraps around at the end or beginning of a line.
                var prevgp = &term.line[y.*][x.*];
                var prevdelim = ISDELIM(prevgp.u);
                var gp: *Glyph = undefined;
                var delim: bool = undefined;
                while (true) {
                    var newx = @as(i33, x.*) + direction;
                    var newy = @as(i33, y.*);
                    if (!(0 <= newx and newx <= term.col - 1)) {
                        newy += direction;
                        newx = @mod(newx + @as(i33, term.col), @as(i33, term.col));
                        if (!(0 <= newy and newy <= term.row - 1))
                            break;
                        var yt: u32 = undefined;
                        var xt: u32 = undefined;
                        if (direction > 0) {
                            yt = y.*;
                            xt = x.*;
                        } else {
                            yt = @intCast(u32, newy);
                            xt = @intCast(u32, newx);
                        }
                        if (!as_attr(term.line[yt][xt].mode).get(.Wrap))
                            break;
                    }

                    if (newx >= term.lineLen(@intCast(u32, newy)))
                        break;

                    gp = &term.line[@intCast(u32, newy)][@intCast(u32, newx)];
                    delim = ISDELIM(gp.u);
                    if ((!as_attr(gp.mode).get(.WDummy) and delim != prevdelim) //
                        or (delim and gp.u != prevgp.u))
                        break;

                    x.* = @intCast(u32, newx);
                    y.* = @intCast(u32, newy);
                    prevgp = gp;
                    prevdelim = delim;
                }
            },
            .SnapLine => {
                // Snap around if the previous line or the current one has attr .Wrap
                // set at its end. Then the whole next or previous line will be selected.
                x.* = if (direction < 0) 0 else term.col - 1;
                if (direction < 0) {
                    while (y.* > 0) : (y.* -= 1) {
                        if (!as_attr(term.line[y.* - 1][term.col - 1].mode).get(.Wrap))
                            break;
                    }
                } else if (direction > 0) {
                    while (y.* < term.row - 1) : (y.* += 1) {
                        if (!as_attr(term.line[y.*][term.col - 1].mode).get(.Wrap))
                            break;
                    }
                }
            },
            .None => {},
        }
    }

    export fn getsel() [*c]u8 {
        return sel.getSelected();
    }
    /// caller owns returned memory
    pub fn getSelected(self: *const Selection) ?[*:0]u8 {
        if (self.ob.x == Selection.no_sel)
            return null;

        const bufsize = (term.col + 1) * (self.ne.y - self.nb.y + 1) * utf_size;
        const str = xmalloc(u8, bufsize);
        var ptr = str;

        // append every set & selected glyph to the selection
        var y = self.nb.y;
        while (y <= self.ne.y) : (y += 1) {
            const linelen = term.lineLen(y);
            if (linelen == 0) {
                ptr.* = '\n';
                ptr += 1;
                continue;
            }

            var gp: [*]Glyph = undefined;
            var lastx: u32 = undefined;
            if (self.@"type" == .Rectangular) {
                gp = term.line[y] + self.nb.x;
                lastx = self.ne.x;
            } else {
                gp = term.line[y] + (if (self.nb.y == y) self.nb.x else 0);
                lastx = if (self.ne.y == y) self.ne.x else term.col - 1;
            }
            var last: [*]Glyph = term.line[y] + std.math.min(lastx, linelen - 1);
            while (@ptrToInt(last) >= @ptrToInt(gp) and last.*.u == ' ')
                last -= 1;

            while (@ptrToInt(gp) <= @ptrToInt(last)) : (gp += 1) {
                if (as_attr(gp.*.mode).get(.WDummy))
                    continue;

                ptr += utf8encode(gp.*.u, ptr);
            }

            // Copy and pasting of line endings is inconsistent
            // in the inconsistent terminal and GUI world.
            // The best solution seems like to produce '\n' when
            // something is copied from st and convert '\n' to
            // '\r', when something to be pasted is received by
            // st.
            // FIXME: Fix the computer world.
            if ((y < self.ne.y or lastx >= linelen) and !as_attr(last.*.mode).get(.Wrap)) {
                ptr.* = '\n';
                ptr += 1;
            }
        }
        ptr.* = 0;
        return @ptrCast([*:0]u8, str);
    }

    export fn selclear() void {
        sel.clear();
    }
    pub fn clear(self: *Selection) void {
        if (self.ob.x == Selection.no_sel) return;
        self.mode = .Idle;
        self.ob.x = Selection.no_sel;
        term.setDirt(self.nb.y, self.ne.y);
    }

    fn scroll(self: *Selection, orig: u32, n: i33) void {
        if (self.ob.x == Selection.no_sel) return;

        if (orig <= self.ob.y and self.ob.y <= term.bot or orig <= self.oe.y and self.oe.y <= term.bot) {
            self.ob.y = @intCast(u32, @as(i33, self.ob.y) + n);
            self.oe.y = @intCast(u32, @as(i33, self.oe.y) + n);
            if (self.ob.y > term.bot or self.oe.y < term.top) {
                self.clear();
                return;
            }
            if (self.@"type" == .Rectangular) {
                if (self.ob.y < term.top)
                    self.ob.y = term.top;
                if (self.oe.y > term.bot)
                    self.oe.y = term.bot;
            } else {
                if (self.ob.y < term.top) {
                    self.ob.y = term.top;
                    self.ob.x = 0;
                }
                if (self.oe.y > term.bot) {
                    self.oe.y = term.bot;
                    self.oe.x = term.col;
                }
            }
            self.normalize();
        }
    }
};

// instance
var term = Terminal{};
const Terminal = struct {
    const TCursor = struct {
        attr: Glyph,
        x: u32 = 0,
        y: u32 = 0,
        state: u8 = 0,
    };
    const CursorMovement = enum { Save, Load };

    row: u32 = 0,
    col: u32 = 0,
    line: [*c]Line = null, // TODO get rid of these filthy [*c]'s
    alt: [*c]Line = null,
    dirty: [*c]bool = null,
    cur: TCursor = undefined,
    ocx: u32 = 0,
    ocy: u32 = 0,
    top: u32 = 0,
    bot: u32 = 0,
    mode: TermMode = TermMode.empty,
    esc: Escape = Escape.empty,
    trantbl: [4]Charset = undefined,
    charset: u32 = 0,
    icharset: u32 = 0,
    tabs: [*c]u32 = null,

    export fn tnew(col: c_int, row: c_int) void {
        term.new(@intCast(u32, col), @intCast(u32, row));
    }
    fn new(self: *Terminal, col: u32, row: u32) void {
        self.* = .{ .cur = .{ .attr = .{ .fg = cfg.defaultfg, .bg = cfg.defaultbg } } };
        self.resize(col, row);
        self.reset();
    }

    export fn tresize(col: c_int, row: c_int) void {
        term.resize(@intCast(u32, col), @intCast(u32, row));
    }
    fn resize(self: *Terminal, new_cols: u32, new_rows: u32) void {
        const minrow = std.math.min(new_rows, self.row);
        const mincol = std.math.min(new_cols, self.col);

        if (new_cols < 1 or new_rows < 1) {
            std.debug.print("tresize: error resizing to {}x{}\n", .{ new_cols, new_rows });
            return;
        }

        // slide screen to keep cursor where we expect it -
        // term.scrollUp would work here, but we can optimize to
        // memmove because we're freeing the earlier lines
        var i: usize = 0;
        while (i <= @as(i33, self.cur.y) - @as(i33, new_rows)) : (i += 1) {
            std.c.free(self.line[i]);
            std.c.free(self.alt[i]);
        }
        // ensure that both src and dst are not null
        if (i > 0) {
            std.mem.copy(Line, self.line[0..self.row], self.line[i .. i + new_rows]);
            std.mem.copy(Line, self.alt[0..self.row], self.alt[i .. i + new_rows]);
        }
        i += new_rows;
        while (i < self.row) : (i += 1) {
            std.c.free(self.line[i]);
            std.c.free(self.alt[i]);
        }

        // resize to new height
        self.line = xrealloc(Line, self.line, new_rows);
        self.alt = xrealloc(Line, self.alt, new_rows);
        self.dirty = xrealloc(bool, self.dirty, new_rows);
        self.tabs = xrealloc(u32, self.tabs, new_cols);

        // resize each new_rows to new width, zero-pad if needed
        i = 0;
        while (i < minrow) : (i += 1) {
            self.line[i] = xrealloc(Glyph, self.line[i], new_cols);
            self.alt[i] = xrealloc(Glyph, self.alt[i], new_cols);
        }
        // ( i = minrow ) now
        while (i < new_rows) : (i += 1) {
            self.line[i] = xmalloc(Glyph, new_cols);
            self.alt[i] = xmalloc(Glyph, new_cols);
        }
        if (new_cols > self.col) {
            var bp = self.tabs + self.col;

            std.mem.set(u32, bp[0..(new_cols - self.col)], 0);
            bp -= 1;
            while (@ptrToInt(bp) > @ptrToInt(self.tabs) and bp[0] != 0) bp -= 1;
            bp += cfg.tabspaces;
            while (@ptrToInt(bp) < @ptrToInt(self.tabs + new_cols)) : (bp += cfg.tabspaces) bp.* = 1;
        }
        // update selfinal size
        self.col = new_cols;
        self.row = new_rows;
        // reset scrolling region
        self.setScroll(0, new_rows - 1);
        // make use of the LIMIT in self.moveTo
        self.moveTo(self.cur.x, self.cur.y);
        // Clearing both screens (it makes all lines dirty)
        const cur = self.cur;
        i = 0;
        while (i < 2) : (i += 1) {
            if (mincol < new_cols and 0 < minrow) {
                self.clearRegion(mincol, 0, new_cols - 1, minrow - 1);
            }
            if (0 < new_cols and minrow < new_rows) {
                self.clearRegion(0, minrow, new_cols - 1, new_rows - 1);
            }
            term.swapScreen();
            self.cursor(.Load);
        }
        self.cur = cur;
    }

    fn setScroll(self: *Terminal, top: u32, bot: u32) void {
        var t = limit(top, 0, self.row - 1);
        var b = limit(bot, 0, self.row - 1);
        if (t > b) {
            const temp = t;
            t = b;
            b = temp;
        }
        self.top = t;
        self.bot = b;
    }

    fn setMode(self: *Terminal, priv: bool, set: bool, args: []u32) void {
        for (args) |arg| {
            if (priv) switch (arg) {
                // DECCKM -- Cursor key
                1 => main.xsetmode(set, main.WindowMode.singleton(.AppCursor)),
                // DECSCNM -- Reverse video
                5 => main.xsetmode(set, main.WindowMode.singleton(.Reverse)),
                // DECOM -- Origin
                6 => {
                    MODBIT(&self.cur.state, set, CURSOR_ORIGIN);
                    self.moveToAbs(0, 0);
                },
                // DECAWM -- Auto wrap
                7 => self.mode.set(.Wrap, set),
                // Error, DECANM -- ANSI/VT52, DECCOLM -- Column, DECSCLM -- Scroll,
                // DECARM -- Auto repeat, DECPFF -- Printer feed, DECPEX -- Printer extent
                // DECNRCM -- National characters, att610 -- Start blinking cursor
                // (-- IGNORED --)
                0, 2, 3, 4, 8, 18, 19, 42, 12 => {},
                // DECTCEM -- Text Cursor Enable Mode
                25 => main.xsetmode(!set, main.WindowMode.singleton(.Hide)),
                // X10 mouse compatibility mode
                9 => {
                    main.xsetpointermotion(false);
                    main.xsetmode(false, main.winmode_mouse);
                    main.xsetmode(set, main.WindowMode.singleton(.MouseX10));
                },
                // 1000: report button press
                1000 => {
                    main.xsetpointermotion(false);
                    main.xsetmode(false, main.winmode_mouse);
                    main.xsetmode(set, main.WindowMode.singleton(.MouseButton));
                },
                // 1002 report motion on button press
                1002 => {
                    main.xsetpointermotion(false);
                    main.xsetmode(false, main.winmode_mouse);
                    main.xsetmode(set, main.WindowMode.singleton(.MouseMany));
                },
                // 1003: enable all mouse motions
                1003 => {
                    main.xsetpointermotion(set);
                    main.xsetmode(false, main.winmode_mouse);
                    main.xsetmode(set, main.WindowMode.singleton(.MouseMany));
                },
                // 1004: extended reporting mode
                1004 => main.xsetmode(set, main.WindowMode.singleton(.Focus)),
                // 1006: extended reporting mode
                1006 => main.xsetmode(set, main.WindowMode.singleton(.MouseSGR)),
                1034 => main.xsetmode(set, main.WindowMode.singleton(.@"8Bit")),
                // swap screen & set/restore cursor as xself
                // swap screen
                // TODO maybe 'repeat myself' more but avoid this if-switch spaghetti
                1049, 47, 1047, 1048 => blk: {
                    if (arg != 1048) {
                        if (arg == 1049) {
                            if (!cfg.allowaltscreen) break :blk;
                            self.cursor(if (set) .Save else .Load);
                        }
                        if (!cfg.allowaltscreen) break :blk;
                        const alt = self.mode.get(.Altscreen);
                        if (alt) self.clearRegion(0, 0, self.col - 1, self.row - 1);
                        if (set != alt) self.swapScreen();
                        if (arg != 1049) break :blk;
                    }
                    self.cursor(if (set) .Save else .Load);
                },
                // 2004: bracketed paste mode
                2004 => main.xsetmode(set, main.WindowMode.singleton(.BrcktPaste)),
                // Not implemented mouse modes. See comments there.
                // mouse highlight mode; can hang the selfinal by design when implemented.
                1001,
                // UTF-8 mouse mode; will confuse applications not supporting UTF-8 and luit.
                1005,
                // urxvt mangled mouse mode; incompatible and can be mistaken for
                // other control codes.
                1015 => {},
                else => {
                    _ = c.fprintf(c.stderr, "erresc: unknown private set/reset mode %d\n", arg);
                },
            } else switch (arg) {
                // Error (IGNORED)
                0 => {},
                2 => main.xsetmode(set, main.WindowMode.singleton(.KeyboardLock)),
                // IRM -- Insertion-replacement
                4 => self.mode.set(.Insert, set),
                // SRM -- Send/Receive
                12 => self.mode.set(.Echo, !set),
                // LNM -- Linefeed/new line
                20 => self.mode.set(.CrLf, set),
                else => {
                    _ = c.fprintf(c.stderr, "erresc: unknown set/reset mode &d\n", arg);
                },
            }
        }
    }

    fn moveTo(self: *Terminal, x: u32, y: u32) void {
        var miny: u32 = undefined;
        var maxy: u32 = undefined;
        if (self.cur.state & CURSOR_ORIGIN != 0) {
            miny = self.top;
            maxy = self.bot;
        } else {
            miny = 0;
            maxy = self.row - 1;
        }
        self.cur.state &= ~CURSOR_WRAPNEXT;
        self.cur.x = limit(x, 0, self.col - 1);
        self.cur.y = limit(y, miny, maxy);
    }

    export fn tattrset(attr: c_int) c_int {
        return @boolToInt(term.isAttrSet(.{ .bits = @intCast(Attr.Bits, attr) }));
    }
    fn isAttrSet(self: *const Terminal, attr: Attr) bool {
        var i: usize = 0;
        while (i < (self.row - 1)) : (i += 1) {
            var j: usize = 0;
            while (j < (self.col - 1)) : (j += 1) {
                if (as_attr(self.line[i][j].mode).any(attr)) return true;
            }
        }
        return false;
    }

    fn clearRegion(self: *Terminal, x_start: u32, y_start: u32, x_end: u32, y_end: u32) void {
        var x1 = x_start;
        var y1 = y_start;
        var x2 = x_end;
        var y2 = y_end;
        if (x1 > x2) {
            const tmp = x1;
            x1 = x2;
            x2 = tmp;
        }
        if (y1 > y2) {
            const tmp = y1;
            y1 = y2;
            y2 = tmp;
        }

        x1 = limit(x1, 0, self.col - 1);
        x2 = limit(x2, 0, self.col - 1);
        y1 = limit(y1, 0, self.row - 1);
        y2 = limit(y2, 0, self.row - 1);
        var y = y1;
        while (y <= y2) : (y += 1) {
            self.dirty[y] = true;
            var x = x1;
            while (x <= x2) : (x += 1) {
                var gp = &self.line[y][x];
                if (sel.isSelected(x, y)) sel.clear();
                gp.fg = self.cur.attr.fg;
                gp.bg = self.cur.attr.bg;
                gp.mode = Attr.empty.bits;
                gp.u = ' ';
            }
        }
    }

    fn lineLen(self: *const Terminal, y: u32) u32 {
        var i = self.col;

        if (as_attr(self.line[y][i - 1].mode).get(.Wrap))
            return i;
        while (i > 0 and self.line[y][i - 1].u == ' ')
            i -= 1;

        return i;
    }

    fn setDirt(self: *Terminal, top: u32, bot: u32) void {
        const t = limit(top, 0, self.row - 1);
        const b = limit(bot, 0, self.row - 1);

        var i: u32 = 0;
        while (i <= b) : (i += 1)
            self.dirty[i] = true;
    }

    export fn tsetdirtattr(attr: c_int) void {
        term.setDirtAttr(.{ .bits = @intCast(Attr.Bits, attr) });
    }
    fn setDirtAttr(self: *Terminal, attr: Attr) void {
        var i: u32 = 0;
        while (i < (self.row - 1)) : (i += 1) {
            var j: u32 = 0;
            while (j < (self.col - 1)) : (j += 1) {
                if (as_attr(self.line[i][j].mode).any(attr)) {
                    self.setDirt(i, i);
                    break;
                }
            }
        }
    }

    fn fullDirt(self: *Terminal) void {
        self.setDirt(0, self.row - 1);
    }

    fn cursor(self: *Terminal, mode: CursorMovement) void {
        const state = struct {
            // persistent
            var saved: [2]TCursor = undefined;
        };
        var alt = @boolToInt(self.mode.get(.Altscreen));

        if (mode == .Save) {
            state.saved[alt] = self.cur;
        } else if (mode == .Load) {
            self.cur = state.saved[alt];
            self.moveTo(state.saved[alt].x, state.saved[alt].y);
        }
    }

    fn reset(self: *Terminal) void {
        self.cur = .{
            .attr = .{
                .mode = Attr.empty.bits,
                .fg = cfg.defaultfg,
                .bg = cfg.defaultbg,
            },
            .x = 0,
            .y = 0,
            .state = CURSOR_DEFAULT,
        };

        std.mem.set(u32, self.tabs[0..self.col], 0);
        var i: u32 = cfg.tabspaces;
        while (i < self.col) : (i += cfg.tabspaces) self.tabs[i] = 1;
        self.top = 0;
        self.bot = self.row - 1;
        self.mode = TermMode.init_with(.{ .Wrap, .Utf8 });
        std.mem.set(Charset, self.trantbl[0..], Charset.Usa);
        self.charset = 0;

        i = 0;
        while (i < 2) : (i += 1) {
            self.moveTo(0, 0);
            self.cursor(.Save);
            self.clearRegion(0, 0, self.col - 1, self.row - 1);
            self.swapScreen();
        }
    }

    fn swapScreen(self: *Terminal) void {
        const temp = self.line;
        self.line = self.alt;
        self.alt = temp;
        self.mode.toggle(.Altscreen);
        self.fullDirt();
    }

    fn scrollDown(self: *Terminal, orig: u32, nlines: u32) void {
        const n = limit(nlines, 0, self.bot - orig + 1);

        self.setDirt(orig, self.bot - n);
        self.clearRegion(0, self.bot - n + 1, self.col - 1, self.bot);

        var i = self.bot;
        while (i >= orig + n) : (i -= 1) {
            const temp = self.line[i];
            self.line[i] = self.line[i - n];
            self.line[i - n] = temp;
        }

        sel.scroll(orig, n);
    }
    fn scrollUp(self: *Terminal, orig: u32, nlines: u32) void {
        const n = limit(nlines, 0, self.bot - orig + 1);

        self.clearRegion(0, orig, self.col - 1, orig + n - 1);
        self.setDirt(orig, self.bot);

        var i = orig;
        while (i <= self.bot - n) : (i += 1) {
            const temp = self.line[i];
            self.line[i] = self.line[i + n];
            self.line[i + n] = temp;
        }

        sel.scroll(orig, -@as(i33, n));
    }

    export fn tdumpsel() void {
        term.dumpSelection();
    }
    fn dumpSelection(self: *Terminal) void {
        if (sel.getSelected()) |ptr| {
            printer(std.mem.span(ptr));
            std.c.free(ptr);
        }
    }

    fn dumpLine(self: *Terminal, n: u32) void {
        var buf: [utf_size]u8 = undefined;
        const l = self.line[n][0 .. std.math.min(self.lineLen(n), self.col) - 1];
        if (l.len != 0 or l[0].u != ' ') {
            for (l) |bp| printer(buf[0..utf8encode(bp.u, &buf)]);
        }
        printer("\n");
    }

    export fn tdump() void {
        term.dump();
    }
    fn dump(self: *Terminal) void {
        var i: u32 = 0;
        while (i < self.row) : (i += 1)
            self.dumpLine(i);
    }

    fn putTab(self: *Terminal, ntabs: i33) void {
        var x = self.cur.x;

        var n = ntabs;
        if (n > 0) {
            while (x < self.col and n != 0) : (n -= 1) {
                x += 1;
                while (x < self.col and self.tabs[x] == 0) x += 1;
            }
        } else if (n < 0) {
            while (x > 0 and n != 0) : (n += 1) {
                x -= 1;
                while (x > 0 and self.tabs[x] == 0) x -= 1;
            }
        }
        self.cur.x = limit(x, 0, self.col - 1);
    }

    fn defUtf8(self: *Terminal, ascii: u8) void {
        self.mode.set(.Utf8, switch (ascii) {
            'G' => true,
            '@' => false,
            else => return,
        });
    }

    fn defTran(self: *Terminal, ascii: u8) void {
        self.trantbl[self.icharset] = switch (ascii) {
            '0' => .Graphic0,
            'B' => .Usa,
            else => {
                _ = c.fprintf(c.stderr, "esc unhandled charset: ESC ( %c\n", ascii);
                return;
            },
        };
    }

    fn decTest(self: *Terminal, ch: u8) void {
        if (ch == '8') {
            var x: u32 = 0;
            var y: u32 = 0;
            while (x < self.col) : (x += 1) while (y < self.row) : (y += 1)
                self.setChar('E', &self.cur.attr, x, y);
        }
    }

    fn strSequence(self: *Terminal, ch: u8) void {
        strescseq.reset();

        strescseq.@"type" = switch (ch) {
            // DCS -- Device Control String
            0x90 => blk: {
                self.esc.set(.DCS, true);
                break :blk 'P';
            },
            // APC -- Application Program Command
            0x9f => '_',
            // PM -- Privacy Message
            0x9e => '^',
            // OSC -- Operating System Command
            0x9d => ']',
            else => ch,
        };
        self.esc.set(.STR, true);
    }

    fn controlCode(self: *Terminal, ascii: u8) void {
        switch (ascii) {
            // HT
            '\t' => {
                self.putTab(1);
                return;
            },
            // BS
            0x08 => {
                self.moveTo(self.cur.x - 1, self.cur.y);
                return;
            },
            // CR
            '\r' => {
                self.moveTo(0, self.cur.y);
                return;
            },
            // LF, VT, FF =>
            '\n', 0x0b, 0x0c => {
                // go to first col if the mode is set
                term.newLine(self.mode.get(.CrLf));
                return;
            },
            // BEL
            0x07 => if (self.esc.get(.StrEnd)) {
                // backwards compatibility to xself
                strescseq.handle();
            } else {
                main.xbell();
            },
            // ESC
            0x1b => {
                csiescseq.reset();
                self.esc.setAll(Escape.init_with(.{ .CSI, .AltCharset, .Test }), false);
                self.esc.set(.Start, true);
                return;
            },
            // SO (LS1 -- Locking shift 1), SI (LS0 -- Locking Shift 0)
            0x0e, 0x0f => {
                self.charset = 1 - (ascii - 0x0e);
                return;
            },
            // SUB
            0x1a => {
                self.setChar('?', &self.cur.attr, self.cur.x, self.cur.y);
                csiescseq.reset();
            },
            // CAN
            0x18 => csiescseq.reset(),
            // ENQ, NUL, XON, XOFF, DEL -- IGNORED
            0x05, 0x00, 0x11, 0x13, 0x7f => return,
            // PAD: TODO
            0x80 => {},
            // HOP: TODO
            0x81 => {},
            // BPH: TODO
            0x82 => {},
            // NBH: TODO
            0x83 => {},
            // IND: TODO
            0x84 => {},
            // NEL -- Next line
            0x85 => self.newLine(true),
            // SSA: TODO
            0x86 => {},
            // ESA: TODO
            0x87 => {},
            // HTS -- Horizontal tab stop
            0x88 => {
                self.tabs[self.cur.x] = 1;
            },
            // HTJ: TODO
            0x89 => {},
            // VTS: TODO
            0x8a => {},
            // PLD: TODO
            0x8b => {},
            // PLU: TODO
            0x8c => {},
            // RI: TODO
            0x8d => {},
            // SS2: TODO
            0x8e => {},
            // SS3: TODO
            0x8f => {},
            // PU1: TODO
            0x91 => {},
            // PU2: TODO
            0x92 => {},
            // STS: TODO
            0x93 => {},
            // CCH: TODO
            0x94 => {},
            // MW: TODO
            0x95 => {},
            // SPA: TODO
            0x96 => {},
            // EPA: TODO
            0x97 => {},
            // SOS: TODO
            0x98 => {},
            // SGCI: TODO
            0x99 => {},
            // DECID -- Identify Terminal
            0x9a => ttywrite(cfg.vtiden, false),
            // CSI: TODO
            0x9b => {},
            // ST: TODO
            0x9c => {},
            // DCS -- Device Control String, OSC -- Operating System Command,
            // PM -- Privacy Message, APC -- Application Program Command
            0x90, 0x9d, 0x9e, 0x9f => {
                self.strSequence(ascii);
                return;
            },
            else => unreachable,
        }
        // only CAN, SUB, BEL and C1 chars interrupt a sequence
        self.esc.setAll(Escape.init_with(.{ .StrEnd, .STR }), false);
    }

    fn escHandle(self: *Terminal, ascii: u8) enum { More, Done } {
        switch (ascii) {
            '[' => {
                self.esc.set(.CSI, true);
                return .Done;
            },
            '#' => {
                self.esc.set(.Test, true);
                return .Done;
            },
            '%' => {
                self.esc.set(.Utf8, true);
                return .Done;
            },
            // DCS -- Device Control String, APC -- Application Program Command,
            // PM -- Privacy Message, OSC -- Operating System Command
            // ('k') -- old title set compatibility
            'P', '_', '^', ']', 'k' => {
                self.strSequence(ascii);
                return .Done;
            },
            // LS2 -- Locking shift 2, LS3 -- Locking shift 3
            'n', 'o' => {
                self.charset = 2 + (ascii - 'n');
            },
            // GZD4 -- set primary charset G0, G1D4 -- set secondary charset G1
            // G2D4 -- set tertiary charset G2, G3D4 -- set quaternary charset G3
            '(', ')', '*', '+' => {
                self.icharset = ascii - '(';
                self.esc.set(.AltCharset, true);
                return .Done;
            },
            // IND -- Linefeed
            'D' => if (self.cur.y == self.bot) {
                term.scrollUp(self.top, 1);
            } else {
                self.moveTo(self.cur.x, self.cur.y + 1);
            },
            // NEL -- Next line
            'E' => {
                term.newLine(true); // always go to first col
            },
            // HTS -- Horizontal tab stop
            'H' => {
                self.tabs[self.cur.x] = 1;
            },
            // RI -- Reverse index
            'M' => if (self.cur.y == self.top) {
                term.scrollDown(self.top, 1);
            } else {
                self.moveTo(self.cur.x, self.cur.y - 1);
            },
            // DECID -- Identify Terminal
            'Z' => ttywrite(cfg.vtiden, false),
            // RIS -- Reset to initial state
            'c' => {
                self.reset();
                resettitle();
                main.xloadcols();
            },
            // DECPAM -- Application keypad
            '=' => main.xsetmode(true, main.WindowMode.init_with(.{.AppKeypad})),
            // DECPNM -- Normal keypad
            '>' => main.xsetmode(true, main.WindowMode.init_with(.{.AppKeypad})),
            // DECSC -- Save Cursor
            '7' => self.cursor(.Save),
            // DECRC -- Restore Cursor
            '8' => self.cursor(.Save),
            // ST -- String Terminator
            '\\' => if (self.esc.get(.StrEnd)) {
                strescseq.handle();
            },
            else => {
                _ = c.fprintf(c.stderr, "erresc: unknown sequence ESC 0x%02X '%c'\n", ascii, if (c.isprint(ascii) != 0) ascii else '.');
            },
        }
        return .More;
    }

    fn putChar(self: *Terminal, u: Rune) void {
        var s: [utf_size]u8 = undefined;
        var width: u32 = undefined;
        var len: usize = undefined;
        const control = ISCONTROL(u);
        if (!self.mode.get(.Utf8) and !self.mode.get(.Sixel)) {
            s[0] = @intCast(u8, u);
            width = 1;
            len = 1;
        } else {
            len = utf8encode(u, &s);
            const wcw = c.wcwidth(@intCast(c_int, u));
            if (!control) {
                width = if (wcw != -1) @intCast(u32, wcw) else blk: {
                    std.mem.copy(u8, &s, &[4]u8{ 0xef, 0xbf, 0xbd, 0 }); // utf_invalid
                    break :blk 1;
                };
            }
        }

        if (self.mode.get(.Print))
            printer(s[0..len]);

        // STR sequence must be checked before anything else
        // because it uses all following characters until it
        // receives a ESC, a SUB, a ST or any other C1 control
        // character.
        str_check: {
            if (self.esc.get(.STR)) {
                if (u == 0x07 or u == 0x18 or u == 0x1a or u == 0x1b or ISCONTROLC1(u)) {
                    self.esc.setAll(Escape.init_with(.{ .Start, .STR, .DCS }), false);
                    if (self.mode.get(.Sixel)) {
                        // TODO: render sixel
                        self.mode.set(.Sixel, false);
                        return;
                    }
                    self.esc.set(.StrEnd, true);
                    break :str_check;
                }

                if (self.mode.get(.Sixel)) {
                    // TODO: implement sixel mode
                    return;
                }
                if (self.esc.get(.DCS) and strescseq.len == 0 and u == 'q')
                    self.mode.set(.Sixel, true);

                if (strescseq.len + len >= strescseq.buf.len - 1) {
                    // Here is a bug in selfinals. If the user never sends
                    // some code to stop the str or esc command, then st
                    // will stop responding. But this is better than
                    // silently failing with unknown characters. At least
                    // then users will report back.
                    //
                    // In the case users ever get fixed, here is the code:

                    // self.esc = 0;
                    // strescseq.handle();
                    return;
                }

                std.mem.copy(u8, strescseq.buf[strescseq.len..], &s);
                strescseq.len += @intCast(u32, len);
                return;
            }
        }
        // Actions of control codes must be performed as soon they arrive
        // because they can be embedded inside a control sequence, and
        // they must not cause conflicts with sequences.
        if (control) {
            self.controlCode(@intCast(u8, u));
            // control codes are not shown ever
            return;
        } else if (self.esc.get(.Start)) {
            const a = @intCast(u8, u);
            if (self.esc.get(.CSI)) {
                csiescseq.buf[csiescseq.len] = a;
                csiescseq.len += 1;
                if ((0x40 <= a and a <= 0x7e) or csiescseq.len >= csiescseq.buf.len - 1) {
                    self.esc = Escape.empty;
                    csiescseq.parse();
                    csiescseq.handle();
                }
                return;
            } else if (self.esc.get(.Utf8)) {
                self.defUtf8(a);
            } else if (self.esc.get(.AltCharset)) {
                self.defTran(a);
            } else if (self.esc.get(.Test)) {
                self.decTest(a);
            } else {
                if (self.escHandle(a) == .Done)
                    return;
                // sequence already finished
            }
            self.esc = Escape.empty;

            // All characters which form part of a sequence are not printed
            return;
        }
        if (sel.ob.x != Selection.no_sel and (sel.ob.y <= self.cur.y and self.cur.y <= sel.oe.y))
            sel.clear();

        var gp = self.line[self.cur.y] + self.cur.x;
        if (self.mode.get(.Wrap) and self.cur.state & CURSOR_WRAPNEXT != 0) {
            gp.*.mode |= Attr.singleton(.Wrap).bits;
            term.newLine(true);
            gp = self.line[self.cur.y] + self.cur.x;
        }

        if (self.mode.get(.Insert) and self.cur.x + width < self.col)
            std.mem.copy(Glyph, gp[width .. self.col - self.cur.x], gp[0 .. self.col - self.cur.x - width]);

        if (self.cur.x + width > self.col) {
            term.newLine(true);
            gp = self.line[self.cur.y] + self.cur.x;
        }

        self.setChar(u, &self.cur.attr, self.cur.x, self.cur.y);

        if (width == 2) {
            gp.*.mode |= Attr.singleton(.Wide).bits;
            if (self.cur.x + 1 < self.col) {
                gp[1].u = 0;
                gp[1].mode = Attr.singleton(.WDummy).bits;
            }
        }
        if (self.cur.x + width < self.col) {
            self.moveTo(self.cur.x + width, self.cur.y);
        } else {
            self.cur.state |= CURSOR_WRAPNEXT;
        }
    }

    export fn twrite(buf_ptr: [*]const u8, buf_len: usize, show_ctrl: c_int) usize {
        return term.write(buf_ptr[0..buf_len], show_ctrl != 0);
    }
    fn write(self: *Terminal, buf: []const u8, show_ctrl: bool) usize {
        var charsize: usize = undefined;
        var n: usize = 0;
        while (n < buf.len) : (n += charsize) {
            var u: Rune = undefined;
            if (self.mode.get(.Utf8) and !self.mode.get(.Sixel)) {
                // process a complete utf8 char
                charsize = utf8decode(buf[n..], &u);
                if (charsize == 0) break;
            } else {
                u = buf[n] & 0xFF;
                charsize = 1;
            }
            if (show_ctrl and ISCONTROL(u)) {
                if (u & 0x80 != 0) {
                    u &= 0x7f;
                    self.putChar('^');
                    self.putChar('[');
                } else if (u != '\n' and u != '\r' and u != '\t') {
                    u ^= 0x40;
                    self.putChar('^');
                }
            }
            self.putChar(u);
        }
        return n;
    }

    fn newLine(self: *Terminal, first_col: bool) void {
        var y = self.cur.y;

        if (y == self.bot) {
            term.scrollUp(self.top, 1);
        } else {
            y += 1;
        }
        self.moveTo(if (first_col) 0 else self.cur.x, y);
    }

    /// for absolute user moves, when decom is set
    fn moveToAbs(self: *Terminal, x: u32, y: u32) void {
        self.moveTo(x, y + if (self.cur.state & CURSOR_ORIGIN != 0) self.top else 0);
    }

    // zig fmt: off
    fn setChar(self: *Terminal, uni: Rune, attr: *Glyph, x: u32, y: u32) void {
        const vt100_0 = [62]?[*]u8{ // 0x41 - 0x7e
            "↑", "↓", "→", "←", "█", "▚", "☃", // A - G
            null, null, null, null, null, null, null, null, // H - O
            null, null, null, null, null, null, null, null, // P - W
            null, null, null, null, null, null, null, " ", // X - _
            "◆", "▒", "␉", "␌", "␍", "␊", "°", "±", // ` - g
            "␤", "␋", "┘", "┐", "┌", "└", "┼", "⎺", // h - o
            "⎻", "─", "⎼", "⎽", "├", "┤", "┴", "┬", // p - w
            "│", "≤", "≥", "π", "≠", "£", "·", // x - ~
        };
        var u = uni;
        // The table is proudly stolen from rxvt
        if (self.trantbl[self.charset] == .Graphic0 and (0x41 <= u and u <= 0x7e))
            if (vt100_0[u - 0x41]) |s| {
                _ = utf8decode(s[0..utf_size], &u);
            };

        if (as_attr(self.line[y][x].mode).get(.Wide)) {
            if (x + 1 < self.col) {
                self.line[y][x + 1].u = ' ';
                self.line[y][x + 1].mode &= ~Attr.singleton(.WDummy).bits;
            }
        } else if (as_attr(self.line[y][x].mode).get(.WDummy)) {
            self.line[y][x - 1].u = ' ';
            self.line[y][x - 1].mode &= ~Attr.singleton(.Wide).bits;
        }

        self.dirty[y] = true;
        self.line[y][x] = attr.*;
        self.line[y][x].u = u;
    }
    // zig fmt: on

    fn deleteChar(self: *Terminal, n_chars: u32) void {
        const n = limit(n_chars, 0, self.col - self.cur.x);

        const dst = self.cur.x;
        const src = self.cur.x + n;
        const size = self.col - src;
        const line = self.line[self.cur.y];

        std.mem.copy(Glyph, line[dst..size], line[src..size]);
        self.clearRegion(self.col - n, self.cur.y, self.col - 1, self.cur.y);
    }

    fn insertBlank(self: *Terminal, n_chars: u32) void {
        const n = limit(n_chars, 0, self.col - self.cur.x);

        const dst = self.cur.x + n;
        const src = self.cur.x;
        const size = self.col - dst;
        const line = self.line[self.cur.y];

        std.mem.copy(Glyph, line[dst..size], line[src..size]);
        self.clearRegion(src, self.cur.y, dst - 1, self.cur.y);
    }

    fn insertBlankLine(self: *Terminal, n_lines: u32) void {
        if (self.top <= self.cur.y and self.cur.y <= self.bot)
            term.scrollDown(self.cur.y, n_lines);
    }
    fn deleteLine(self: *Terminal, n_lines: u32) void {
        if (self.top <= self.cur.y and self.cur.y <= self.bot)
            term.scrollUp(self.cur.y, n_lines);
    }
    fn defColor(attr: []u32, npar: *u32) ?u32 {
        return switch (attr[npar.* + 1]) {
            // direct color in RGB space
            2 => blk: {
                if (npar.* + 4 >= attr.len) {
                    _ = c.fprintf(c.stderr, "erresc(38): Incorrect number of parameters (%d)\n", npar.*);
                    return null;
                }
                const r = attr[npar.* + 2];
                const g = attr[npar.* + 3];
                const b = attr[npar.* + 4];
                npar.* += 4;
                if (!(0 <= r and r <= 255) or
                    !(0 <= g and g <= 255) or
                    !(0 <= b and b <= 255))
                {
                    _ = c.fprintf(c.stderr, "erresc: bad rgb color(%u,%u,%u)\n", r, g, b);
                    return null;
                }
                break :blk TRUECOLOR(r, g, b);
            },
            // indexed color
            5 => blk: {
                if (npar.* + 2 >= attr.len) {
                    _ = c.fprintf(c.stderr, "erresc(38): Incorrect number of parameters (%d)\n", npar.*);
                    return null;
                }
                npar.* += 2;
                const idx = attr[npar.*];
                if (!(0 <= idx and idx <= 255)) {
                    _ = c.fprintf(c.stderr, "erresc: bad fgcolor %d\n", idx);
                    return null;
                }
                break :blk idx;
            },
            // missing
            // 0: implemented defined (only foreground),
            // 1: transparent,
            // 3: direct color in CMY space,
            // 4: direct color in CMYK space,
            else => {
                _ = c.fprintf(c.stderr, "erresc(38): gfx attr %d unknown\n", attr[npar.*]);
                return null;
            },
        };
    }
    fn setAttr(self: *Terminal, attrs: []u32) void {
        // not using a for loop since the index can be advanced by defColor()
        var i: u32 = 0;
        while (i < attrs.len) : (i += 1) {
            const attr = attrs[i];
            switch (attr) {
                0 => {
                    self.cur.attr.mode &= ~Attr.init_with(.{
                        .Bold,
                        .Faint,
                        .Italic,
                        .Underline,
                        .Blink,
                        .Reverse,
                        .Invisible,
                        .Struck,
                    }).bits;
                    self.cur.attr.fg = cfg.defaultfg;
                    self.cur.attr.bg = cfg.defaultbg;
                },
                1...9 => self.cur.attr.mode |= Attr.singleton(switch (attr) {
                    1 => .Bold,
                    2 => .Faint,
                    3 => .Italic,
                    4 => .Underline,
                    5, 6 => .Blink,
                    7 => .Reverse,
                    8 => .Invisible,
                    9 => .Struck,
                    else => unreachable,
                }).bits,
                22 => self.cur.attr.mode &= ~Attr.init_with(.{ .Bold, .Faint }).bits,
                23...25, 27...29 => self.cur.attr.mode &= ~Attr.singleton(switch (attr) {
                    23 => .Italic,
                    24 => .Underline,
                    25 => .Blink,
                    27 => .Reverse,
                    28 => .Invisible,
                    29 => .Struck,
                    else => unreachable,
                }).bits,
                30...37 => self.cur.attr.fg = attr - 30,
                38 => if (defColor(attrs, &i)) |idx| {
                    self.cur.attr.fg = idx;
                },
                39 => self.cur.attr.fg = cfg.defaultfg,
                40...47 => self.cur.attr.bg = attr - 40,
                48 => if (defColor(attrs, &i)) |idx| {
                    self.cur.attr.bg = idx;
                },
                49 => self.cur.attr.bg = cfg.defaultbg,
                90...97 => self.cur.attr.fg = attr - 90 + 8,
                100...107 => self.cur.attr.bg = attr - 100 + 8,
                else => {
                    _ = c.fprintf(
                        c.stderr,
                        "erresc(default): gfx attr &d unknown\n",
                        attr,
                    );
                    csiescseq.dump();
                },
            }
        }
    }

    fn printer(s: []const u8) void {
        external.tprinter(s.ptr, s.len);
    }

    export fn tisset(flag: c_int) c_int {
        return @as(c_int, term.mode.bits) & flag;
    }
    export fn tgetrow() c_int {
        return @intCast(c_int, term.row);
    }
    export fn tgetcol() c_int {
        return @intCast(c_int, term.col);
    }

    export fn tsetprint(to: c_int) void {
        if (to < 0)
            term.mode.toggle(.Print)
        else
            term.mode.set(.Print, to != 0);
    }
};

// instance
var csiescseq = CSIEscape{};
/// CSI Escape sequence state and related functions
/// Sequence structure:
///     `ESC '[' [[ [<priv>] <arg> [;]] <mode> [<mode>]]`
const CSIEscape = struct {
    buf: [esc_buf_size]u8 = undefined,
    len: u32 = 0,
    priv: bool = false,
    arg: [esc_arg_size]u32 = undefined,
    narg: u32 = 0,
    mode: [2]u8 = [_]u8{0} ** 2,

    pub fn parse(self: *CSIEscape) void {
        var p = @ptrCast([*:0]const u8, &self.buf);
        self.narg = 0;
        if (p[0] == '?') {
            self.priv = true;
            p += 1;
        }

        self.buf[self.len] = 0;
        while (@ptrToInt(p) < @ptrToInt(&self.buf) + self.len) {
            var np: [*:0]const u8 = undefined;
            var v = c.strtol(p, &np, 10);
            if (np == p)
                v = 0;
            if (v == std.math.maxInt(c_long) or v == std.math.minInt(c_long))
                v = std.math.maxInt(u32);
            self.arg[self.narg] = @intCast(u32, v);
            self.narg += 1;
            p = np;
            if (p[0] != ';' or self.narg == esc_arg_size)
                break;
            p += 1;
        }
        self.mode[0] = p[0];
        p += 1;
        self.mode[1] = if (@ptrToInt(p) < @ptrToInt(&self.buf) + self.len) p[0] else 0;
    }

    pub fn handle(self: *CSIEscape) void {
        var unknown = false;
        switch (self.mode[0]) {
            // ICH -- Insert <n> blank char
            '@' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.insertBlank(self.arg[0]);
            },
            // CUU -- Cursor <n> Up
            'A' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(term.cur.x, term.cur.y - self.arg[0]);
            },
            // CUD, VPR -- Cursor <n> Down
            'B', 'e' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(term.cur.x, term.cur.y + self.arg[0]);
            },
            // MC -- Media Copy
            'i' => switch (self.arg[0]) {
                0 => term.dump(),
                1 => term.dumpLine(term.cur.y),
                2 => term.dumpSelection(),
                4 => term.mode.set(.Print, false),
                5 => term.mode.set(.Print, true),
                else => {},
            },
            // DA -- Device Attributes
            'c' => if (self.arg[0] == 0)
                ttywrite(cfg.vtiden, false),
                // CUF, HPR -- Cursor <N> Forward
            'C', 'a' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(term.cur.x + self.arg[0], term.cur.y);
            },
            // CUB -- Cursor <N> Forward
            'D' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(term.cur.x - self.arg[0], term.cur.y);
            },
            // CNL -- Cursor <n> Down and first col
            'E' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(0, term.cur.y + self.arg[0]);
            },
            // CPL -- Cursor <n> Up and first col
            'F' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(0, term.cur.y - self.arg[0]);
            },
            // TBC -- Tabulation clear
            'g' => switch (self.arg[0]) {
                0 => { // clear current tab stop
                    term.tabs[term.cur.x] = 0;
                },
                3 => { // clear all the tabs
                    std.mem.set(u32, term.tabs[0..term.col], 0);
                },
                else => {
                    unknown = true;
                },
            },
            // CHA, HPA -- Move to <col>
            'G', '`' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveTo(self.arg[0] - 1, term.cur.y);
            },
            // CUP, HVP -- Move to <row> <col>
            'H', 'f' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                if (self.arg[1] == 0) self.arg[1] = 1;
                term.moveToAbs(self.arg[1] - 1, self.arg[0] - 1);
            },
            // CHT -- Cursor Forward Tabulation <n> tab stops
            'I' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.putTab(self.arg[0]);
            },
            // ED -- Clear screen
            'J' => switch (self.arg[0]) {
                0 => { // below
                    term.clearRegion(term.cur.x, term.cur.y, term.col - 1, term.cur.y);
                    if (term.cur.y < term.row - 1) {
                        term.clearRegion(0, term.cur.y + 1, term.col - 1, term.row - 1);
                    }
                },
                1 => { // above
                    if (term.cur.y > 1)
                        term.clearRegion(0, 0, term.col - 1, term.cur.y - 1);
                    term.clearRegion(0, term.cur.y, term.cur.x, term.cur.y);
                },
                2 => { // all
                    term.clearRegion(0, 0, term.col - 1, term.row - 1);
                },
                else => {
                    unknown = true;
                },
            },
            // EL -- Clear line
            'K' => switch (self.arg[0]) {
                0 => { // right
                    term.clearRegion(term.cur.x, term.cur.y, term.col - 1, term.cur.y);
                },
                1 => { // left
                    term.clearRegion(0, term.cur.y, term.cur.x, term.cur.y);
                },
                2 => { // all
                    term.clearRegion(0, term.cur.y, term.col - 1, term.cur.y);
                },
                else => {},
            },
            // SU -- Scroll <n> line up
            'S' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.scrollUp(term.top, self.arg[0]);
            },
            // SD -- Scroll <n> line down
            'T' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.scrollDown(term.top, self.arg[0]);
            },
            // IL -- Insert <n> blank lines
            'L' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.insertBlankLine(self.arg[0]);
            },
            // RM -- Reset Mode
            'l' => {
                term.setMode(self.priv, false, self.arg[0..self.narg]);
            },
            // DL -- Delete <n> lines
            'M' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.deleteLine(self.arg[0]);
            },
            // ECH -- Erase <n> char
            'X' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.clearRegion(term.cur.x, term.cur.y, term.cur.x + self.arg[0] - 1, term.cur.y);
            },
            // DCH -- Delete <n> char
            'P' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.deleteChar(self.arg[0]);
            },
            // CBT -- Cursor Backward Tabulation <n> tab stops
            'Z' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.putTab(-@as(i33, self.arg[0]));
            },
            // VPA -- Move to <row>
            'd' => {
                if (self.arg[0] == 0) self.arg[0] = 1;
                term.moveToAbs(term.cur.x, self.arg[0] - 1);
            },
            // SM -- Set terminal mode
            'h' => {
                term.setMode(self.priv, true, self.arg[0..self.narg]);
            },
            // SGR -- Terminal attribute (color)
            'm' => {
                term.setAttr(self.arg[0..self.narg]);
            },
            // DSR -- Device Status Report (cursor position)
            'n' => if (self.arg[0] == 6) {
                var buf: [40]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "\x1b[{};{}R", .{ term.cur.y + 1, term.cur.x + 1 }) catch unreachable;
                ttywrite(str, false);
            },
            // DECSTBM -- Set Scrolling region
            'r' => if (self.priv) {
                unknown = true;
            } else {
                if (self.arg[0] == 0) self.arg[0] = 1;
                if (self.arg[1] == 0) self.arg[1] = term.row;
                term.setScroll(self.arg[0] - 1, self.arg[1] - 1);
                term.moveToAbs(0, 0);
            },
            // DECSC -- Save cursor position (ANSI.SYS)
            's' => {
                term.cursor(.Save);
            },
            // DECRC -- Restore cursor position (ANSI.SYS)
            'u' => {
                term.cursor(.Load);
            },
            ' ' => switch (self.mode[1]) {
                'q' => if (!main.xsetcursor(self.arg[0])) {
                    unknown = true;
                },
                else => {
                    unknown = true;
                },
            },
            else => {
                unknown = true;
            },
        }
        if (unknown) {
            _ = c.fprintf(c.stderr, "erresc: unknown csi ");
            csiescseq.dump();
        }
    }

    fn dump(self: *CSIEscape) void {
        _ = c.fprintf(c.stderr, "ESC[");
        var i: u32 = 0;
        while (i < self.len) : (i += 1) {
            var ch = self.buf[i] & 0xff;
            if (c.isprint(ch) != 0) {
                _ = c.putc(ch, c.stderr);
            } else switch (ch) {
                '\n' => _ = c.fprintf(c.stderr, "(\\n)"),
                '\r' => _ = c.fprintf(c.stderr, "(\\r)"),
                0x1b => _ = c.fprintf(c.stderr, "(\\e)"),
                else => _ = c.fprintf(c.stderr, "(%02x)", ch),
            }
        }
        _ = c.putc('\n', c.stderr);
    }

    fn reset(self: *CSIEscape) void {
        self.* = .{};
    }
};

// instance
var strescseq = STREscape{};
/// STR Escape sequence structs
/// `ESC type [[ [<priv>] <arg> [;]] <mode>] ESC '\'`
const STREscape = struct {
    @"type": u8 = 0,
    buf: [str_buf_size]u8 = undefined,
    len: u32 = 0,
    args: [str_arg_size][*:0]u8 = undefined,
    narg: u32 = 0,

    fn handle(self: *STREscape) void {
        term.esc.setAll(Escape.init_with(.{ .StrEnd, .STR }), false);
        self.parse();
        const narg = self.narg;
        const par = if (narg != 0) c.atoi(self.args[0]) else 0;

        switch (self.@"type") {
            // OSC -- Operating System Command
            ']' => switch (par) {
                0, 1, 2 => {
                    if (narg > 1) main.xsettitle(self.args[1]);
                    return;
                },
                52 => {
                    if (narg > 2) {
                        const decoded = base64dec(self.args[2]);
                        if (decoded) |dec| {
                            main.xsetsel(dec);
                            main.xclipcopy();
                        } else {
                            _ = c.fprintf(c.stderr, "erresc: invalid base64\n");
                        }
                    }
                    return;
                },
                // color set
                4, 104 => blk: {
                    var p: ?[*:0]u8 = null;
                    if (par == 4) {
                        if (narg < 3) break :blk;
                        p = self.args[2];
                    }
                    const j = if (narg > 1) @intCast(i32, c.atoi(self.args[1])) else -1;
                    if (!main.xsetcolorname(j, p)) {
                        if (par == 104 and narg <= 1)
                            return; // color reset without parameter
                        _ = c.fprintf(c.stderr, "erresc: invalid color j=%d, p=%s\n", j, p orelse "(null)");
                    } else {
                        // TODO if defaultbg color is changed, borders are dirty
                        redraw();
                    }
                    return;
                },
                else => {},
            },
            // old title set compatibility
            'k' => {
                main.xsettitle(self.args[0]);
                return;
            },
            // DCS -- Device Control String
            'P' => {
                term.esc.set(.DCS, true);
                return;
            },
            // APC -- Application Program Command, PM -- Privacy Message
            '_', '^' => return,
            else => {}, // error handled below
        }

        _ = c.fprintf(c.stderr, "erresc: unknown str ");
        self.dump();
    }
    fn parse(self: *STREscape) void {
        var p: [*]u8 = &self.buf;
        self.narg = 0;
        self.buf[self.len] = 0;

        if (p[0] == 0) return;

        while (self.narg < str_arg_size) {
            self.args[self.narg] = @ptrCast([*:0]u8, p);
            self.narg += 1;
            while (p[0] != ';' and p[0] != 0) p += 1;
            if (p[0] == 0) return;
            p[0] = 0;
            p += 1;
        }
    }
    fn dump(self: *STREscape) void {
        _ = c.fprintf(c.stderr, "ESC%c", self.@"type");
        var i: u32 = 0;
        while (i < self.len) : (i += 1) {
            var ch = self.buf[i] & 0xff;
            if (ch == 0) {
                _ = c.putc('\n', c.stderr);
                return;
            } else if (c.isprint(ch) != 0) {
                _ = c.putc(ch, c.stderr);
            } else switch (ch) {
                '\n' => _ = c.fprintf(c.stderr, "(\\n)"),
                '\r' => _ = c.fprintf(c.stderr, "(\\r)"),
                0x1b => _ = c.fprintf(c.stderr, "(\\e)"),
                else => _ = c.fprintf(c.stderr, "(%02x)", ch),
            }
        }
        _ = c.fprintf(c.stderr, "ESC\\\n");
    }

    fn reset(self: *STREscape) void {
        self.* = .{};
    }
};

fn xwrite(fd: os.fd_t, str: []const u8) !void {
    var written: usize = 0;
    while (written != str.len) {
        written += try os.write(fd, str[written..]);
    }
}

// Compromise between C and Zig style (temporary solution)
fn xmalloc(comptime T: type, len: usize) [*]T {
    return @ptrCast([*]T, @alignCast(@alignOf(T), external.xmalloc(len * @sizeOf(T))));
}

fn xrealloc(comptime T: type, p: ?[*]T, len: usize) [*]T {
    return @ptrCast([*]T, @alignCast(@alignOf(T), external.xrealloc(@ptrCast(?*c_void, p), len * @sizeOf(T))));
}

fn ttywrite(s: []const u8, may_echo: bool) void {
    external.ttywrite(s.ptr, s.len, @boolToInt(may_echo));
}

fn utf8decode(ch: []const u8, u: *Rune) usize {
    u.* = utf_invalid;
    if (ch.len == 0) return 0;
    var len: usize = undefined;
    var udecoded = utf8decodebyte(ch[0], &len);
    if (!(1 <= len and len <= utf_size)) return 1;
    var i: usize = 1;
    var j: usize = 1;
    while (i < ch.len and j < len) : ({
        i += 1;
        j += 1;
    }) {
        var chtype: usize = undefined;
        udecoded = (udecoded << 6) | utf8decodebyte(ch[i], &chtype);
        if (chtype != 0) return j;
    }
    if (j < len)
        return 0;
    u.* = udecoded;
    _ = utf8validate(u, len);

    return len;
}
fn utf8decodebyte(ch: u8, i: *usize) Rune {
    i.* = 0;
    while (i.* < utfmask.len) : (i.* += 1) {
        if ((ch & utfmask[i.*]) == utfbyte[i.*])
            return ch & ~utfmask[i.*];
    }
    return 0;
}
pub export fn utf8encode(uni: Rune, ch: [*]u8) usize {
    var u = uni;
    const len = utf8validate(&u, 0);
    if (len > utf_size)
        return 0;

    var i: usize = len - 1;
    while (i > 0) : (i -= 1) {
        ch[i] = utf8encodebyte(u, 0);
        u >>= 6;
    }
    ch[0] = utf8encodebyte(u, len);

    return len;
}
fn utf8encodebyte(u: Rune, i: usize) u8 {
    return @truncate(u8, utfbyte[i] | (u & ~utfmask[i]));
}
fn utf8validate(u: *Rune, i: usize) usize {
    if (!(utfmin[i] <= u.* and u.* <= utfmax[i]) or (0xD800 <= u.* and u.* <= 0xDFFF))
        u.* = utf_invalid;
    var ni: usize = 1;
    while (u.* > utfmax[ni]) ni += 1;
    return ni;
}

const base64_digits = [_]u8{
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  62, 0,  0,  0,  63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0,  0,  0,  255, 0,  0,  0,  0,  1,  2,  3,  4,  5,  6,
    7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,  21, 22, 23, 24, 25, 0,  0,  0,  0,  0,
    0,  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,  39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
    49, 50, 51, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   0,
};

fn base64dec_getc(source: *[*:0]const u8) u8 {
    var src = source;
    while ((src.*)[0] != 0 and c.isprint((src.*)[0]) == 0) src.* += 1;
    src.* += 1;
    return (src.* - 1)[0];
}

fn base64dec(source: [*:0]const u8) ?[*:0]u8 {
    var src = source;
    var in_len: usize = std.mem.len(src);

    if (in_len % 4 != 0)
        in_len += 4 - (in_len % 4);
    var dst = xmalloc(u8, in_len / 4 * 3 + 1);
    const result = @ptrCast([*:0]u8, dst);
    while (src[0] != 0) {
        const da = base64_digits[base64dec_getc(&src)];
        const db = base64_digits[base64dec_getc(&src)];
        const dc = base64_digits[base64dec_getc(&src)];
        const dd = base64_digits[base64dec_getc(&src)];

        dst[0] = (da << 2) | ((db & 0x30) >> 4);
        dst += 1;
        if (dc == 255) break;
        dst[0] = ((db & 0x0f) << 4) | ((dc & 0x3c) >> 2);
        dst += 1;
        if (dd == 255) break;
        dst[0] = ((dc & 0x03) << 6) | dd;
        dst += 1;
    }
    dst[0] = 0;
    return result;
}

pub fn die(comptime msg: []const u8, params: anytype) noreturn {
    std.debug.print(msg, params);
    os.exit(1);
}

export fn redraw() void {
    term.fullDirt();
    draw();
}

fn drawregion(x1: u32, y1: u32, x2: u32, y2: u32) void {
    var y = y1;
    while (y < y2) : (y += 1) {
        if (!term.dirty[y]) continue;

        term.dirty[y] = false;
        main.xdrawline(term.line[y], x1, y, x2);
    }
}

export fn draw() void {
    var cx = term.cur.x;
    if (!main.xstartdraw()) return;
    term.ocx = limit(term.ocx, 0, term.col - 1);
    term.ocy = limit(term.ocy, 0, term.row - 1);
    if (as_attr(term.line[term.ocy][term.ocx].mode).get(.WDummy))
        term.ocx -= 1;
    if (as_attr(term.line[term.cur.y][cx].mode).get(.WDummy))
        cx -= 1;
    drawregion(0, 0, term.col, term.row);
    main.xdrawcursor(
        cx,
        term.cur.y,
        term.line[term.cur.y][cx],
        term.ocx,
        term.ocy,
        term.line[term.ocy][term.ocx],
    );
    term.ocx = cx;
    term.ocy = term.cur.y;
    main.xfinishdraw();
    main.xximspot(term.ocx, term.ocy);
}

const resettitle = external.resettitle;
