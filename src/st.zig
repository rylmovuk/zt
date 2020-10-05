const std = @import("std");
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
pub inline fn TIMEDIFF(t1: c.struct_timespec, t2: c.struct_timespec) c_long {
    return (t1.tv_sec - t2.tv_sec) * 1000 + @divTrunc(t1.tv_nsec - t2.tv_nsec, 1_000_000);
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

const SelectionMode = enum { Idle, Empty, Ready };
const SelectionType = enum(u2) { Regular = 1, Rectangular = 2 };
pub const SelectionSnap = enum(u2) { None = 0, SnapWord = 1, SnapLine = 2 };
pub const Rune = u32;

pub const Glyph = struct {
    u: Rune = 0,
    mode: Attr = Attr.empty,
    fg: u32,
    bg: u32,
};

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
    return u and c.wcschr(cfg.worddelimiters, @intCast(c.wchar_t, u)) != null;
}

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

const CursorMovement = enum { Save, Load };

const CURSOR_DEFAULT: u8 = 0;
const CURSOR_WRAPNEXT: u8 = 1;
const CURSOR_ORIGIN: u8 = 2;

const Charset = enum { Graphic0, Graphic1, Uk, Usa, Multi, Ger, Fin };

const ESC_START = 1;
const ESC_CSI = 2;
const ESC_STR = 4; // OSC, PM, APC
const ESC_ALTCHARSET = 8;
const ESC_STR_END = 16; // a final string was encountered
const ESC_TEST = 32; // Enter in test mode
const ESC_UTF8 = 64;
const ESC_DCS = 128;

const TCursor = struct {
    attr: Glyph,
    x: u32 = 0,
    y: u32 = 0,
    state: u8 = 0,
};

const Selection = struct {
    const Coords = struct { x: u32 = 0, y: u32 = 0 };

    mode: SelectionMode,
    @"type": SelectionType,
    snap: SelectionSnap,
    nb: Coords,
    ne: Coords,
    ob: Coords,
    oe: Coords,
    alt: bool,
};

const Term = struct {
    row: u32 = 0,
    col: u32 = 0,
    line: [*c]Line = null,
    alt: [*c]Line = null,
    dirty: [*c]bool = null,
    c: TCursor,
    ocx: u32 = 0,
    ocy: u32 = 0,
    top: u32 = 0,
    bot: u32 = 0,
    mode: TermMode = TermMode.empty,
    esc: u32 = 0,
    trantbl: [4]Charset = undefined,
    charset: u32 = 0,
    icharset: u32 = 0,
    tabs: [*c]u32 = null,
};

/// CSI Escape sequence structs
/// ESC '[' [[ [<priv>] <arg> [;]] <mode> [<mode>]]
const CSIEscape = struct {
    buf: [esc_buf_size]u8,
    len: usize,
    priv: u8,
    arg: [esc_arg_size]u32,
    narg: usize,
    mode: [2]u8,
};

/// STR Escape sequence structs
/// ESC type [[ [<priv>] <arg> [;]] <mode>] ESC '\'
const STREscape = struct {
    @"type": u8,
    buf: [str_buf_siz]u8,
    len: usize,
    args: [str_arg_siz][]const u8,
    narg: usize,
};

// Globals
var term: Term = undefined;
var sel: Selection = undefined;
var csi_esc_seq: CSIEscape = undefined;
var str_esc_seq: STREscape = undefined;
var iofd: c_int = 1;
var cmdfd: c_int = undefined;
var pid: c.pid_t = undefined;

const utfbyte = [utf_size + 1]u8{ 0x80, 0, 0xC0, 0xE0, 0xF0 };
const utfmask = [utf_size + 1]u8{ 0xC0, 0x80, 0xE0, 0xF0, 0xF8 };
const utfmin = [utf_size + 1]Rune{ 0, 0, 0x80, 0x800, 0x10000 };
const utfmax = [utf_size + 1]Rune{ 0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF };

fn xwrite(fd: c_int, str: []const u8) isize {
    var left = str.len;
    var s = str.ptr;

    while (left > 0) {
        const written = c.write(fd, s, left);
        if (written < 0) return written;
        const r = @intCast(usize, written);
        left -= r;
        s += r;
    }

    return @intCast(isize, str.len);
}
pub fn xmalloc(len: usize) *c_void {
    const p = c.malloc(len);
    return p orelse die("malloc: {}\n", .{c.strerror(std.c._errno().*)});
}
pub fn xrealloc(p: *allowzero c_void, len: usize) *c_void {
    const newp = c.realloc(p, len);
    return newp orelse die("realloc: {}\n", .{@as([*:0]const u8, c.strerror(std.c._errno().*))});
}
pub fn xstrdup(s: [*:0]u8) [*:0]u8 {
    const ns = @as(?[*:0]u8, c.strdup(s));
    return ns orelse die("strdup: {}\n", .{c.strerror(std.c._errno().*)});
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
pub fn utf8encode(uni: Rune, ch: [*:0]u8) usize {
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
fn base64dec_getc(src: *[*:0]const u8) u8 {
    @compileError("TODO base64dec_getc");
}
fn base64dec(src: [*:0]const u8) [*:0]u8 {
    @compileError("TODO base64dec");
}

pub fn selinit() void {
    sel.mode = .Idle;
    sel.snap = .None;
    sel.ob.x = std.math.maxInt(u32);
}

fn tlinelen(y: u32) u32 {
    var i = term.col;

    if (term.line[y][i - 1].mode.get(.Wrap))
        return i;
    while (i > 0 and term.line[y][i - 1].u == ' ')
        i -= 1;

    return i;
}
pub fn selstart(col: u32, row: u32, snap: SelectionSnap) void {
    selclear();
    sel.mode = .Empty;
    sel.@"type" = .Regular;
    sel.alt = term.mode.get(.Altscreen);
    sel.snap = snap;
    sel.oe.x = col;
    sel.ob.x = col;
    sel.oe.y = row;
    sel.ob.y = row;
    selnormalize();

    if (sel.snap != .None) sel.mode = .Ready;
    tsetdirt(sel.nb.y, sel.ne.y);
}
fn selextend(col: u32, row: u32, type: SelectionType, done: bool) void {
    @compileError("TODO selextend");
}
fn selnormalize() void {
    @compileError("TODO selnormalize");
}
pub fn selected(x: u32, y: u32) bool {
    if (sel.mode == .Empty or sel.ob.x == std.math.maxInt(u32) or sel.alt != term.mode.get(.Altscreen))
        return false;

    if (sel.@"type" == .Rectangular)
        return sel.nb.y <= y and y <= sel.ne.y;

    return (sel.nb.y <= y and y <= sel.ne.y) //
        and (y != sel.nb.y or x >= sel.nb.x) //
        and (y != sel.ne.y or x <= sel.ne.x);
}
fn selsnap(x: *u32, y: *u32, direction: u32) void {
    @compileError("TODO selsnap");
}
fn getsel() ?[*:0]u8 {
    @compileError("TODO getsel");
}
fn selclear() void {
    if (sel.ob.x == std.math.maxInt(u32)) return;
    sel.mode = .Idle;
    sel.ob.x = std.math.maxInt(u32);
    tsetdirt(sel.nb.y, sel.ne.y);
}

pub fn die(comptime msg: []const u8, params: anytype) noreturn {
    std.debug.print(msg, params);
    std.os.exit(1);
}

fn execsh(cmd: [*:0]const u8, arguments: ?[*:null]const ?[*:0]const u8) void {
    std.c._errno().* = 0;
    const pw = @as(?*c.struct_passwd, c.getpwuid(c.getuid())) orelse {
        if (std.c._errno().* != 0)
            die("getpwuid: {}\n", .{c.strerror(std.c._errno().*)})
        else
            die("who are you?\n", .{});
    };

    const sh = @ptrCast(?[*:0]const u8, c.getenv("SHELL")) orelse
        if (pw.pw_shell[0] != 0) @as([*:0]const u8, pw.pw_shell) else cmd;

    var prog = if (arguments) |args|
        args[0]
    else if (cfg.utmp) |utmp|
        utmp
    else
        sh;
    const args = arguments orelse &[_:null]?[*:0]const u8{prog};

    _ = c.unsetenv("COLUMNS");
    _ = c.unsetenv("LINES");
    _ = c.unsetenv("TERMCAP");
    _ = c.setenv("LOGNAME", pw.pw_name, 1);
    _ = c.setenv("USER", pw.pw_name, 1);
    _ = c.setenv("SHELL", sh, 1);
    _ = c.setenv("HOME", pw.pw_dir, 1);
    _ = c.setenv("TERM", cfg.termname, 1);

    const SIG_DFL = null;
    _ = c.signal(c.SIGCHLD, SIG_DFL);
    _ = c.signal(c.SIGHUP, SIG_DFL);
    _ = c.signal(c.SIGINT, SIG_DFL);
    _ = c.signal(c.SIGQUIT, SIG_DFL);
    _ = c.signal(c.SIGTERM, SIG_DFL);
    _ = c.signal(c.SIGALRM, SIG_DFL);

    // another monstrosity because of wrong qualifiers on C pointers
    _ = c.execvp(prog, @intToPtr([*c]const [*c]u8, @ptrToInt(args)));
    c._exit(1);
}
fn sigchld(a: c_int) callconv(.C) void {
    @compileError("TODO sigchld");
}
fn stty(arguments: ?[*:null]const ?[*:0]const u8) void {
    var cmd: [c._POSIX_ARG_MAX]u8 = undefined;
    var n = cfg.stty_args.len;
    if (n > cmd.len - 1)
        die("incorrect stty parameters\n", .{});
    std.mem.copy(u8, cmd[0..], cfg.stty_args);
    var q = cmd[n..];
    if (arguments) |args| {
        var p = args;
        while (p.*) |s| : (p += 1) {
            const a = std.mem.span(s);
            if (a.len > q.len - 1)
                die("stty parameter length too long\n", .{});
            q[0] = ' ';
            std.mem.copy(u8, q[1..], a);
            q = q[a.len + 1 ..];
        }
    }
    q[0] = 0;
    if (c.system(&cmd) != 0)
        c.perror("Couldn't call stty");
}
pub fn ttynew(line: ?[*:0]const u8, cmd: [*:0]const u8, out: ?[*:0]const u8, args: ?[*:null]const ?[*:0]const u8) std.os.fd_t {
    var m: c_int = undefined;
    var s: c_int = undefined;
    if (out != null) {
        term.mode.set(.Print, true);
        iofd = if (c.strcmp(out, "-") == 0) 1 else c.open(out, c.O_WRONLY | c.O_CREAT, 0o666);
        if (iofd < 0) {
            _ = c.fprintf(c.stderr, "Error opening %s:%s\n", out, c.strerror(std.c._errno().*));
        }
    }
    if (line != null) {
        cmdfd = c.open(line, c.O_RDWR);
        if (cmdfd < 0)
            die("open line '{}' failed: {}\n", .{ line, c.strerror(std.c._errno().*) });
        _ = c.dup2(cmdfd, 0);
        stty(args);
        return cmdfd;
    }
    // seems to work fine on linux, openbsd and freebsd
    if (c.openpty(&m, &s, null, null, null) < 0) die("openpty failed: {}\n", .{c.strerror(std.c._errno().*)});
    pid = c.fork();
    switch (pid) {
        -1 => die("fork failed: {}\n", .{c.strerror(std.c._errno().*)}),
        0 => {
            _ = c.close(iofd);
            _ = c.setsid(); // create a new process group
            _ = c.dup2(s, 0);
            _ = c.dup2(s, 1);
            _ = c.dup2(s, 2);
            if (c.ioctl(s, c.TIOCSCTTY, null) < 0)
                die("ioctl TIOCSCTTY failed: {}\n", .{c.strerror(std.c._errno().*)});
            _ = c.close(s);
            _ = c.close(m);
            if (std.builtin.os.tag == .openbsd) {
                if (c.pledge("stdio getpw proc exec", null) == -1) die("pledge\n", .{});
            }
            execsh(cmd, args);
        },
        else => {
            if (std.builtin.os.tag == .openbsd) {
                if (c.pledge("stdio rpath tty proc", null) == -1) die("pledge\n", .{});
            }
            _ = c.close(s);
            cmdfd = m;
            _ = c.signal(c.SIGCHLD, sigchld);
        },
    }
    return cmdfd;
}
var ttyread_buf = [_]u8{0} ** c.BUFSIZ;
var ttyread_buflen: usize = 0;
pub fn ttyread() usize {
    var written: usize = undefined;
    var ret = c.read(cmdfd, &ttyread_buf + ttyread_buflen, ttyread_buf.len - ttyread_buflen);
    if (ret < 0)
        die("couldn't read from shell: {}\n", .{c.strerror(std.c._errno().*)});
    ttyread_buflen += @intCast(usize, ret);
    written = twrite(ttyread_buf[0..ttyread_buflen], false);
    ttyread_buflen -= written;
    // keep any uncomplete utf8 char for the next call
    if (ttyread_buflen > 0)
        std.mem.copy(u8, ttyread_buf[0..], ttyread_buf[written .. written + ttyread_buflen]);
    return @intCast(usize, ret);
}
pub fn ttywrite(str: []const u8, may_echo: bool) void {
    if (may_echo and term.mode.get(.Echo))
        _ = twrite(str, true);

    if (!term.mode.get(.CrLf)) {
        ttywriteraw(str);
        return;
    }

    // This is similar to how the kernel handles ONLCR for ttys
    var i: usize = 0;
    while (i < str.len) {
        var n: usize = undefined;
        if (str[i] == '\r') {
            n = 1;
            ttywriteraw("\r\n");
        } else {
            n = std.mem.indexOfScalar(u8, str[i..], '\r') orelse str.len - i;
            ttywriteraw(str[i .. i + n]);
        }
        i += n;
    }
}
fn ttywriteraw(s: []const u8) void {
    var lim: usize = 256;

    // Remember that we are using a pty, which might be a modem line.
    // Writing too much will clog the line. That's why we are doing this
    // dance.
    // FIXME: Migrate the world to Plan 9.
    var i: usize = 0;
    while (i < s.len) {
        const n = s.len - i;
        var wfd: c.fd_set = undefined;
        var rfd: c.fd_set = undefined;
        c._FD_ZERO(&wfd);
        c._FD_ZERO(&rfd);
        c._FD_SET(cmdfd, &wfd);
        c._FD_SET(cmdfd, &rfd);

        // Check if we can write.
        if (c.pselect(cmdfd + 1, &rfd, &wfd, null, null, null) < 0) {
            if (std.c._errno().* == c.EINTR) continue;
            die("select failed: {}\n", .{c.strerror(std.c._errno().*)});
        }
        if (c._FD_ISSET(cmdfd, &wfd)) {
            // Only write the bytes written by ttywrite() or the
            // default of 256. This seems to be a reasonable value
            // for a serial line. Bigger values might clog the I/O.
            const written = c.write(cmdfd, s[i..].ptr, std.math.min(n, lim));
            if (written < 0)
                die("write error on tty: {}\n", .{c.strerror(std.c._errno().*)});
            const r = @intCast(usize, written);
            if (r < n) {
                // We weren't able to write out everything.
                // This means the buffer is getting full again. Empty it.
                if (n < lim) lim = ttyread();
                i += r;
            } else {
                // All bytes have been written.
                break;
            }
        }
        if (c._FD_ISSET(cmdfd, &rfd))
            lim = ttyread();
    }
    return;
}
pub fn ttyresize(tw: u32, th: u32) void {
    var w: c.struct_winsize = .{
        .ws_row = @intCast(c_ushort, term.row),
        .ws_col = @intCast(c_ushort, term.col),
        .ws_xpixel = @intCast(c_ushort, tw),
        .ws_ypixel = @intCast(c_ushort, th),
    };
    if (c.ioctl(cmdfd, c.TIOCSWINSZ, &w) < 0)
        _ = c.fprintf(c.stderr, "Couldn't set window size: %s\n", c.strerror(std.c._errno().*));
}
pub fn ttyhangup() void {
    // Send SIGHUP to shell
    _ = c.kill(pid, c.SIGHUP);
}
pub fn tattrset(attr: Attr.Elem) bool {
    // Send SIGHUP to shell
    var i: usize = 0;
    while (i < (term.row - 1)) : (i += 1) {
        var j: usize = 0;
        while (j < (term.col - 1)) : (j += 1) {
            if (term.line[i][j].mode.get(attr)) return true;
        }
    }
    return false;
}

fn tsetdirt(top: u32, bot: u32) void {
    const t = limit(top, 0, term.row - 1);
    const b = limit(bot, 0, term.row - 1);

    var i: u32 = 0;
    while (i <= b) : (i += 1)
        term.dirty[i] = true;
}

pub fn tsetdirtattr(attr: Attr.Elem) void {
    var i: u32 = 0;
    while (i < (term.row - 1)) : (i += 1) {
        var j: u32 = 0;
        while (j < (term.col - 1)) : (j += 1) {
            if (term.line[i][j].mode.get(attr)) {
                tsetdirt(i, i);
                break;
            }
        }
    }
}

fn tfulldirt() void {
    tsetdirt(0, term.row - 1);
}

var tcursor_c: [2]TCursor = undefined;
fn tcursor(mode: CursorMovement) void {
    var alt = @boolToInt(term.mode.get(.Altscreen));

    if (mode == .Save) {
        tcursor_c[alt] = term.c;
    } else if (mode == .Load) {
        term.c = tcursor_c[alt];
        tmoveto(tcursor_c[alt].x, tcursor_c[alt].y);
    }
}

fn treset() void {
    term.c = .{
        .attr = .{
            .mode = Attr.empty,
            .fg = cfg.defaultfg,
            .bg = cfg.defaultbg,
        },
        .x = 0,
        .y = 0,
        .state = CURSOR_DEFAULT,
    };

    std.mem.set(u32, term.tabs[0..term.col], 0);
    var i: u32 = cfg.tabspaces;
    while (i < term.col) : (i += cfg.tabspaces) term.tabs[i] = 1;
    term.top = 0;
    term.bot = term.row - 1;
    term.mode = TermMode.init_with(.{ .Wrap, .Utf8 });
    std.mem.set(Charset, term.trantbl[0..], Charset.Usa);
    term.charset = 0;

    i = 0;
    while (i < 2) : (i += 1) {
        tmoveto(0, 0);
        tcursor(.Save);
        tclearregion(0, 0, term.col - 1, term.row - 1);
        tswapscreen();
    }
}

pub fn tnew(col: u32, row: u32) void {
    term = .{ .c = .{ .attr = .{ .fg = cfg.defaultfg, .bg = cfg.defaultbg } } };
    tresize(col, row);
    treset();
}

fn tswapscreen() void {
    const temp = term.line;
    term.line = term.alt;
    term.alt = temp;
    term.mode.toggle(.Altscreen);
    tfulldirt();
}

fn tscrolldown(orig: u32, n: u32) void {
    @compileError("TODO tscrolldown");
}
fn tscrollup(orig: u32, n: u32) void {
    @compileError("TODO tscrollup");
}
fn selscroll(orig: u32, n: u32) void {
    @compileError("TODO selscroll");
}
fn tnewline(first_col: u32) void {
    @compileError("TODO tnewline");
}
fn csiparse() void {
    @compileError("TODO csiparse");
}
fn tmoveato(x: u32, y: u32) void {
    @compileError("TODO tmoveato");
}

fn tmoveto(x: u32, y: u32) void {
    var miny: u32 = undefined;
    var maxy: u32 = undefined;
    if (term.c.state & CURSOR_ORIGIN != 0) {
        miny = term.top;
        maxy = term.bot;
    } else {
        miny = 0;
        maxy = term.row - 1;
    }
    term.c.state &= ~CURSOR_WRAPNEXT;
    term.c.x = limit(x, 0, term.col - 1);
    term.c.y = limit(y, miny, maxy);
}

fn tsetchar(u: Rune, attr: *Glyph, x: u32, y: u32) void {
    @compileError("TODO tsetchar");
}
fn tclearregion(x_start: u32, y_start: u32, x_end: u32, y_end: u32) void {
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

    x1 = limit(x1, 0, term.col - 1);
    x2 = limit(x2, 0, term.col - 1);
    y1 = limit(y1, 0, term.row - 1);
    y2 = limit(y2, 0, term.row - 1);
    var y = y1;
    while (y <= y2) : (y += 1) {
        term.dirty[y] = true;
        var x = x1;
        while (x <= x2) : (x += 1) {
            var gp = &term.line[y][x];
            if (selected(x, y)) selclear();
            gp.fg = term.c.attr.fg;
            gp.bg = term.c.attr.bg;
            gp.mode = Attr.empty;
            gp.u = ' ';
        }
    }
}
fn tdeletechar(n: u32) void {
    @compileError("TODO tdeletechar");
}
fn tinsertblank(n: u32) void {
    @compileError("TODO tinsertblank");
}
fn tinsertblankline(n: u32) void {
    @compileError("TODO tinsertblankline");
}
fn tdeleteline(n: u32) void {
    @compileError("TODO tdeleteline");
}
fn tdefcolor(attr: *u32, npar: *u32, l: u32) u32 {
    @compileError("TODO tdefcolor");
}
fn tsetattr(attr: *u32, l: u32) void {
    @compileError("TODO tsetattr");
}

fn tsetscroll(top: u32, bot: u32) void {
    var t = limit(top, 0, term.row - 1);
    var b = limit(bot, 0, term.row - 1);
    if (t > b) {
        const temp = t;
        t = b;
        b = temp;
    }
    term.top = t;
    term.bot = b;
}

fn tsetmode(priv: u32, set: u32, args: [*]u32, narg: usize) void {
    @compileError("TODO tsetmode");
}
fn csihandle() void {
    @compileError("TODO csihandle");
}
fn csidump() void {
    @compileError("TODO csidump");
}
fn csireset() void {
    @compileError("TODO csireset");
}
fn strhandle() void {
    @compileError("TODO strhandle");
}
fn strparse() void {
    @compileError("TODO strparse");
}
fn strdump() void {
    @compileError("TODO strdump");
}
fn strreset() void {
    strescseq = std.mem.zeroes(STREscape);
}
pub fn sendbreak(arg: *const Arg) void {
    if (c.tcsendbreak(cmdfd, 0) != 0)
        c.perror("Error sending break");
}
fn tprinter(s: []const u8) void {
    if (iofd != -1 and xwrite(iofd, s) < 0) {
        c.perror("Error writing to output file");
        _ = c.close(iofd);
        iofd = -1;
    }
}
pub fn toggleprinter(_: *const Arg) void {
    term.mode.toggle(.Print);
}
pub fn printscreen(_: *const Arg) void {
    tdump();
}
pub fn printsel(_: *const Arg) void {
    tdumpsel();
}
fn tdumpsel() void {
    if (getsel()) |ptr| {
        tprinter(std.mem.span(ptr));
        c.free(ptr);
    }
}
fn tdumpline(n: u32) void {
    @compileError("TODO tdumpline");
}
fn tdump() void {
    var i: u32 = 0;
    while (i < term.row) : (i += 1)
        tdumpline(i);
}
fn tputtab(n: u32) void {
    @compileError("TODO tputtab");
}
fn tdefutf8(ascii: u8) void {
    @compileError("TODO tdefutf8");
}
fn tdeftran(ascii: u8) void {
    @compileError("TODO tdeftran");
}
fn tdectest(c: u8) void {
    @compileError("TODO tdectest");
}
fn tstrsequence(c: u8) void {
    @compileError("TODO tstrsequence");
}
fn tcontrolcode(ascii: u8) void {
    @compileError("TODO tcontrolcode");
}
fn eschandle(ascii: u8) bool {
    @compileError("TODO eschandle");
}
fn tputc(u: Rune) void {
    @compileError("TODO tputc");
}
fn twrite(buf: []const u8, show_ctrl: bool) usize {
    var charsize: usize = undefined;
    var n: usize = 0;
    while (n < buf.len) : (n += charsize) {
        var u: Rune = undefined;
        if (term.mode.get(.Utf8) and !term.mode.get(.Sixel)) {
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
                tputc('^');
                tputc('[');
            } else if (u != '\n' and u != '\r' and u != '\t') {
                u ^= 0x40;
                tputc('^');
            }
        }
        tputc(u);
    }
    return n;
}

pub fn tresize(col: u32, row: u32) void {
    const minrow = std.math.min(row, term.row);
    const mincol = std.math.min(col, term.col);

    if (col < 1 or row < 1) {
        std.debug.warn("tresize: error resizing to {}x{}\n", .{ col, row });
        return;
    }

    // slide screen to keep cursor where we expect it -
    // tscrollup would work here, but we can optimize to
    // memmove because we're freeing the earlier lines
    var i: usize = 0;
    while (i <= @as(i33, term.c.y) - @as(i33, row)) : (i += 1) {
        c.free(term.line[i]);
        c.free(term.alt[i]);
    }
    // ensure that both src and dst are not null
    if (i > 0) {
        std.mem.copy(Line, term.line[0..term.row], term.line[i .. i + row]);
        std.mem.copy(Line, term.alt[0..term.row], term.alt[i .. i + row]);
    }
    i += row;
    while (i < term.row) : (i += 1) {
        c.free(term.line[i]);
        c.free(term.alt[i]);
    }

    // resize to new height
    term.line = @ptrCast([*]Line, @alignCast(@alignOf([*]Line), xrealloc(@ptrCast(*allowzero c_void, term.line), row * @sizeOf(Line))));
    term.alt = @ptrCast([*]Line, @alignCast(@alignOf([*]Line), xrealloc(@ptrCast(*allowzero c_void, term.alt), row * @sizeOf(Line))));
    term.dirty = @ptrCast([*]bool, @alignCast(@alignOf([*]bool), xrealloc(@ptrCast(*allowzero c_void, term.dirty), row * @sizeOf(bool))));
    term.tabs = @ptrCast([*]u32, @alignCast(@alignOf([*]u32), xrealloc(@ptrCast(*allowzero c_void, term.tabs), col * @sizeOf(u32))));

    // resize each row to new width, zero-pad if needed
    i = 0;
    while (i < minrow) : (i += 1) {
        term.line[i] = @ptrCast(Line, @alignCast(@alignOf(Line), xrealloc(term.line[i], col * @sizeOf(Glyph))));
        term.alt[i] = @ptrCast(Line, @alignCast(@alignOf(Line), xrealloc(term.alt[i], col * @sizeOf(Glyph))));
    }
    // ( i = minrow ) now
    while (i < row) : (i += 1) {
        term.line[i] = @ptrCast(Line, @alignCast(@alignOf(Line), xmalloc(col * @sizeOf(Glyph))));
        term.alt[i] = @ptrCast(Line, @alignCast(@alignOf(Line), xmalloc(col * @sizeOf(Glyph))));
    }
    if (col > term.col) {
        var bp = term.tabs + term.col;

        std.mem.set(u32, bp[0..(col - term.col)], 0);
        bp -= 1;
        while (@ptrToInt(bp) > @ptrToInt(term.tabs) and bp[0] != 0) bp -= 1;
        bp += cfg.tabspaces;
        while (@ptrToInt(bp) < @ptrToInt(term.tabs + col)) : (bp += cfg.tabspaces) bp.* = 1;
    }
    // update terminal size
    term.col = col;
    term.row = row;
    // reset scrolling region
    tsetscroll(0, row - 1);
    // make use of the LIMIT in tmoveto
    tmoveto(term.c.x, term.c.y);
    // Clearing both screens (it makes all lines dirty)
    const cur = term.c;
    i = 0;
    while (i < 2) : (i += 1) {
        if (mincol < col and 0 < minrow) {
            tclearregion(mincol, 0, col - 1, minrow - 1);
        }
        if (0 < col and minrow < row) {
            tclearregion(0, minrow, col - 1, row - 1);
        }
        tswapscreen();
        tcursor(.Load);
    }
    term.c = cur;
}

fn drawregion(x1: u32, y1: u32, x2: u32, y2: u32) void {
    var y = y1;
    while (y < y2) : (y += 1) {
        if (!term.dirty[y]) continue;

        term.dirty[y] = false;
        main.xdrawline(term.line[y], x1, y, x2);
    }
}
pub fn draw() void {
    var cx = term.c.x;
    if (!main.xstartdraw()) return;
    term.ocx = limit(term.ocx, 0, term.col - 1);
    term.ocy = limit(term.ocx, 0, term.row - 1);
    if (term.line[term.ocy][term.ocx].mode.get(.WDummy))
        term.ocx -= 1;
    if (term.line[term.c.y][cx].mode.get(.WDummy))
        cx -= 1;
    drawregion(0, 0, term.col, term.row);
    main.xdrawcursor(
        cx,
        term.c.y,
        term.line[term.c.y][cx],
        term.ocx,
        term.ocy,
        term.line[term.ocy][term.ocx],
    );
    term.ocx = cx;
    term.ocy = term.c.y;
    main.xfinishdraw();
    main.xximspot(term.ocx, term.ocy);
}
pub fn redraw() void {
    tfulldirt();
    draw();
}
