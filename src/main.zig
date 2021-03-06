const program_version = "0.0.0"; // TODO
const program_name = "st";

const std = @import("std");
const clap = @import("deps/clap");
const cfg = @import("config.zig");
const c = @import("c.zig");
const st = @import("st.zig");

const Bitset = @import("util.zig").Bitset;
const Glyph = st.Glyph;

pub const Shortcut = struct {
    mod: u32,
    keysym: c.KeySym,
    func: fn (*const Arg) void,
    arg: Arg,

    pub fn init(mod: u32, keysym: c.KeySym, func: fn (*const Arg) void, arg: Arg) Shortcut {
        return .{ .mod = mod, .keysym = keysym, .func = func, .arg = arg };
    }
};

pub const MouseShortcut = struct {
    b: u32,
    mask: u32,
    s: [*:0]const u8,

    pub fn init(b: u32, mask: u32, s: [*:0]const u8) MouseShortcut {
        return .{ .b = b, .mask = mask, .s = s };
    }
};

pub const Key = struct {
    k: c.KeySym,
    mask: u32,
    s: [*:0]const u8,
    // three-valued logic variables: 0 indifferent, 1 on, -1 off
    appkey: i3,
    appcursor: i3,

    pub fn init(k: c.KeySym, mask: u32, s: [*:0]const u8, appkey: i3, appcursor: i3) Key {
        return .{ .k = k, .mask = mask, .s = s, .appkey = appkey, .appcursor = appcursor };
    }
};

pub const XK_ANY_MOD = std.math.maxInt(u32);
pub const XK_NO_MOD: u32 = 0;
pub const XK_SWITCH_MOD: u32 = 1 << 13;

const Arg = st.Arg;
const die = st.die;

const XEMBED_FOCUS_IN = 4;
const XEMBED_FOCUS_OUT = 4;

const WindowMode = Bitset(enum {
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
const winmode_mouse = &WindowMode.init_with(.{ .MouseButton, .MouseMotion, .MouseX10, .MouseMany });
// Purely graphic info
const TermWindow = struct {
    /// tty width and height
    tw: u32,
    th: u32,
    /// window width and height
    w: u32,
    h: u32,
    /// char height
    ch: u32,
    /// char width
    cw: u32,
    /// window state/mode flags
    mode: WindowMode,
    /// cursor style
    cursor: u32 = cursorshape,
};
const XWindow = struct {
    dpy: *c.Display,
    cmap: c.Colormap,
    win: c.Window,
    buf: c.Drawable,
    /// font spec buffer used for rendering
    specbuf: [*]c.XftGlyphFontSpec,
    xembed: c.Atom,
    wmdeletewin: c.Atom,
    netwmname: c.Atom,
    netwmpid: c.Atom,
    xim: c.XIM,
    xic: c.XIC,
    draw: *c.XftDraw,
    vis: *c.Visual,
    attrs: c.XSetWindowAttributes,
    scr: c_int,
    /// is fixed geometry?
    isfixed: bool = false,
    l: c_int = 0,
    t: c_int = 0,
    gm: c_int,
};

const XSelection = struct {
    xtarget: c.Atom,
    primary: ?[*:0]u8,
    clipboard: ?[*:0]u8,
    tclick1: c.timespec,
    tclick2: c.timespec,
};

const Font = struct {
    height: u32,
    width: u32,
    ascent: u32,
    descent: u32,
    badslant: u32,
    badweight: u32,
    lbearing: u16,
    rbearing: u16,
    match: *c.XftFont,
    set: ?*c.FcFontSet,
    pattern: *c.FcPattern,
};

const DrawingContext = struct {
    col: []c.XftColor,
    font: Font,
    bfont: Font,
    ifont: Font,
    ibfont: Font,
    gc: c.GC,
};

const handler = comptime blk: {
    var h = [_]?(fn (*c.XEvent) void){null} ** c.LASTEvent;
    h[c.KeyPress] = kpress;
    h[c.ClientMessage] = cmessage;
    h[c.ConfigureNotify] = resize;
    h[c.VisibilityNotify] = visibility;
    h[c.UnmapNotify] = unmap;
    h[c.Expose] = expose;
    h[c.FocusIn] = focus;
    h[c.FocusOut] = focus;
    h[c.MotionNotify] = bmotion;
    h[c.ButtonPress] = bpress;
    h[c.ButtonRelease] = brelease;
    // Uncomment if you want the selection to disappear when you select something
    // different in another window.
    // h[c.SelectionClear] = selclear_;
    h[c.SelectionNotify] = selnotify;

    // PropertyNotify is only turned on when there is some INCR transfer happening
    // for the selection retrieval.
    h[c.PropertyNotify] = propnotify;
    h[c.SelectionRequest] = selrequest;
    break :blk h;
};

// Globals
var dc: DrawingContext = undefined;
var xw: XWindow = undefined;
var xsel: XSelection = undefined;
var win: TermWindow = undefined;

const Fontcache = struct {
    font: *c.XftFont,
    flags: u32,
    unicodep: st.Rune,
};
var frc: []Fontcache = undefined;
var frccap: usize = 0;
var usedfont: [*:0]const u8 = undefined;
var usedfontsize: f64 = 0;
var defaultfontsize: f64 = 0;

var opt_class: ?[*:0]const u8 = null;
var opt_cmd: ?[*:null]?[*:0]const u8 = null;
var opt_embed: ?[*:0]const u8 = null;
var opt_font: ?[*:0]const u8 = null;
var opt_io: ?[*:0]const u8 = null;
var opt_line: ?[*:0]const u8 = null;
var opt_name: ?[*:0]const u8 = null;
// guaranteed by main to be nonnull
var opt_title: ?[*:0]const u8 = null;

pub fn clipcopy(_: *const Arg) void {
    c.free(xsel.clipboard);
    xsel.clipboard = null;

    if (xsel.primary) |prim| {
        xsel.clipboard = st.xstrdup(prim);
        const clipboard = c.XInternAtom(xw.dpy, "CLIPBOARD", 0);
        _ = c.XSetSelectionOwner(xw.dpy, clipboard, xw.win, c.CurrentTime);
    }
}
pub fn clippaste(_: *const Arg) void {
    const clipboard = c.XInternAtom(xw.dpy, "CLIPBOARD", 0);
    _ = c.XConvertSelection(
        xw.dpy,
        clipboard,
        xsel.xtarget,
        clipboard,
        xw.win,
        c.CurrentTime,
    );
}
pub fn selpaste(_: *const Arg) void {
    _ = c.XConvertSelection(
        xw.dpy,
        c.XA_PRIMARY,
        xsel.xtarget,
        c.XA_PRIMARY,
        xw.win,
        c.CurrentTime,
    );
}
pub fn numlock(_: *const Arg) void {
    win.mode.toggle(.Numlock);
}
pub fn zoom(arg: *const Arg) void {
    const larg = Arg{ .f = usedfontsize + arg.f };
    zoomabs(&larg);
}
pub fn zoomabs(arg: *const Arg) void {
    xunloadfonts();
    xloadfonts(usedfont, arg.f);
    cresize(0, 0);
    st.redraw();
    xhints();
}
pub fn zoomreset(dummy: *const Arg) void {
    if (defaultfontsize > 0) {
        const larg = Arg{ .f = defaultfontsize };
        zoomabs(&larg);
    }
}

fn evcol(e: *c.XEvent) u32 {
    var x = @intCast(u32, e.xbutton.x) - cfg.borderpx;
    x = st.limit(x, 0, win.tw - 1);
    return x / win.cw;
}
fn evrow(e: *c.XEvent) u32 {
    var y = @intCast(u32, e.xbutton.y) - cfg.borderpx;
    y = st.limit(y, 0, win.th - 1);
    return y / win.ch;
}

fn mousesel(e: *c.XEvent, done: c_int) void {
    const state = e.xbutton.state & ~@as(c_uint, c.Button1Mask | cfg.forceselmod);

    const seltype = for (cfg.selmasks[1..]) |mask, typ| {
        if (match(mask, state)) {
            break @intToEnum(st.SelectionType, @intCast(u2, typ));
        }
    } else st.SelectionType.Regular;
    st.selextend(evcol(e), evrow(e), seltype, done != 0);
    if (done != 0)
        setsel(st.getsel(), e.xbutton.time);
}
var mousereport_ox: u32 = 0;
var mousereport_oy: u32 = 0;
var oldbutton: u32 = 3; // button event on startup: 3 = release
fn mousereport(e: *c.XEvent) void {
    const x = evcol(e);
    const y = evcol(e);
    var button = e.xbutton.button;

    // from urxvt
    if (e.xbutton.@"type" == c.MotionNotify) {
        if (x == mousereport_ox and y == mousereport_oy)
            return;
        if (!win.mode.get(.MouseMotion) and !win.mode.get(.MouseMany))
            return;
        // MOUSE_MOTION: no reporting if no button is pressed
        if (win.mode.get(.MouseMotion) and oldbutton == 3)
            return;

        button = oldbutton + 32;
        mousereport_ox = x;
        mousereport_oy = y;
    } else {
        if (!win.mode.get(.MouseSGR) and e.xbutton.@"type" == c.ButtonRelease) {
            button = 3;
        } else {
            button -= c.Button1;
            if (button >= 3)
                button += 64 - 3;
        }
        if (e.xbutton.@"type" == c.ButtonPress) {
            oldbutton = button;
            mousereport_ox = x;
            mousereport_oy = y;
        } else if (e.xbutton.@"type" == c.ButtonRelease) {
            oldbutton = 3;
            // WindowMode.MouseX10: no button release reporting
            if (win.mode.get(.MouseX10))
                return;
            if (button == 64 or button == 65)
                return;
        }
    }

    const state = e.xbutton.state;
    if (!win.mode.get(.MouseX10)) {
        button += @as(c_uint, if (state & c.ShiftMask != 0) 4 else 0) //
            + @as(c_uint, if (state & c.Mod4Mask != 0) 8 else 0) //
            + @as(c_uint, if (state & c.ControlMask != 0) 16 else 0);
    }

    var buf: [40]u8 = undefined;
    const esc_str = if (win.mode.get(.MouseSGR))
        std.fmt.bufPrint(&buf, "\x1b[<{};{};{}{c}", .{
            button,
            x + 1,
            y + 1,
            @as(u8, if (e.xbutton.@"type" == c.ButtonRelease) 'm' else 'M'),
        }) catch unreachable
    else if (x < 223 and y < 223)
        std.fmt.bufPrint(&buf, "\x1b[m{c}{c}{c}", .{
            @intCast(u8, 32 + button),
            @intCast(u8, 32 + x + 1),
            @intCast(u8, 32 + y + 1),
        }) catch unreachable
    else
        return;

    st.ttywrite(esc_str, false);
}
fn bpress(e: *c.XEvent) void {
    var now: c.struct_timespec = undefined;
    var snap: st.SelectionSnap = undefined;
    if (win.mode.any(winmode_mouse) and e.xbutton.state & cfg.forceselmod == 0) {
        mousereport(e);
        return;
    }
    for (cfg.mshortcuts) |ms| {
        if (e.xbutton.button == ms.b and match(ms.mask, e.xbutton.state)) {
            st.ttywrite(std.mem.span(ms.s), true);
            return;
        }
    }

    if (e.xbutton.button == c.Button1) {
        // If the user clicks below predefined timeouts specific
        // snapping behaviour is exposed.
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
        if (st.TIMEDIFF(now, xsel.tclick2) <= cfg.tripleclicktimeout) {
            snap = .SnapLine;
        } else if (st.TIMEDIFF(now, xsel.tclick1) <= cfg.doubleclicktimeout) {
            snap = .SnapWord;
        } else {
            snap = .None;
        }
        xsel.tclick2 = xsel.tclick1;
        xsel.tclick1 = now;
        st.selstart(evcol(e), evrow(e), snap);
    }
}
fn propnotify(e: *c.XEvent) void {
    const clipboard = c.XInternAtom(xw.dpy, "CLIPBOARD", 0);

    const xpev = &e.xproperty;
    if (xpev.state == c.PropertyNewValue and (xpev.atom == c.XA_PRIMARY or xpev.atom == clipboard)) {
        selnotify(e);
    }
}
fn selnotify(e: *c.XEvent) void {
    var incratom = c.XInternAtom(xw.dpy, "INCR", 0);
    var property = if (e.@"type" == c.SelectionNotify)
        e.xselection.property
    else if (e.@"type" == c.PropertyNotify)
        e.xproperty.atom
    else
        return;

    var ofs: usize = 0;
    while (true) {
        var typ: c.Atom = undefined;
        var format: c_int = undefined;
        var nitems: usize = undefined;
        var rem: usize = undefined;
        var data: [*c]u8 = undefined;
        if (c.XGetWindowProperty(
            xw.dpy,
            xw.win,
            property,
            @intCast(c_long, ofs),
            c.BUFSIZ / 4,
            c.False,
            c.AnyPropertyType,
            &typ,
            &format,
            &nitems,
            &rem,
            &data,
        ) != 0) {
            _ = c.fprintf(c.stderr, "Clipboard allocation failed\n");
            return;
        }
        if (e.@"type" == c.PropertyNotify and nitems == 0 and rem == 0) {
            // If there is some PropertyNotify with no data, then
            // this is the signal of the selection owner that all
            // data has been transferred. We won't need to receive
            // PropertyNotify events anymore.
            st.MODBIT(&xw.attrs.event_mask, false, c.PropertyChangeMask);
            _ = c.XChangeWindowAttributes(xw.dpy, xw.win, c.CWEventMask, &xw.attrs);
        }
        if (typ == incratom) {
            // Activate the PropertyNotify events so we receive
            // when the selection owner does send us the next
            // chunk of data.
            st.MODBIT(&xw.attrs.event_mask, true, c.PropertyChangeMask);
            _ = c.XChangeWindowAttributes(xw.dpy, xw.win, c.CWEventMask, &xw.attrs);
            // Deleting the property is the transfer start signal.
            _ = c.XDeleteProperty(xw.dpy, xw.win, property);
            continue;
        }
        // As seen in getsel:
        // Line endings are inconsistent in the terminal and GUI world
        // copy and pasting. When receiving some selection data,
        // replace all '\n' with '\r'.
        // FIXME: Fix the computer world.
        for (data[0 .. nitems * @intCast(usize, format) / 8]) |*ch| {
            if (ch.* == '\n')
                ch.* = '\r';
        }

        if (win.mode.get(.BrcktPaste) and ofs == 0)
            st.ttywrite("\x1b[200~", false);
        st.ttywrite(data[0 .. nitems * @intCast(usize, format) / 8], true);
        if (win.mode.get(.BrcktPaste) and rem == 0)
            st.ttywrite("\x1b[201~", false);
        _ = c.XFree(data);

        ofs += nitems * @intCast(usize, format) / 32;
        if (rem <= 0) break;
    }
    // Deleting the property again tells the selection owner to send the
    // next data chunk in the property.
    _ = c.XDeleteProperty(xw.dpy, xw.win, property);
}
fn xclipcopy() void {
    clipcopy(Arg.None);
}
fn selclear_(e: *c.XEvent) void {
    st.selclear();
}
fn selrequest(e: *c.XEvent) void {
    var xsre = @ptrCast(*c.XSelectionRequestEvent, e);
    var xev: c.XSelectionEvent = undefined;
    xev.@"type" = c.SelectionNotify;
    xev.requestor = xsre.requestor;
    xev.selection = xsre.selection;
    xev.target = xsre.target;
    xev.time = xsre.time;
    if (xsre.property == c.None) xsre.property = xsre.target;

    // reject
    xev.property = c.None;
    const xa_targets = c.XInternAtom(xw.dpy, "TARGETS", 0);
    if (xsre.target == xa_targets) {
        // respond with the supported type
        var string = xsel.xtarget;
        _ = c.XChangeProperty(
            xsre.display,
            xsre.requestor,
            xsre.property,
            c.XA_ATOM,
            32,
            c.PropModeReplace,
            @ptrCast([*]u8, &string),
            1,
        );
        xev.property = xsre.property;
    } else if (xsre.target == xsel.xtarget or xsre.target == c.XA_STRING) {
        // xith XA_STRING non ascii characters may be incorrect in the
        // requestor. It is not our problem, use utf8.
        const clipboard = c.XInternAtom(xw.dpy, "CLIPBOARD", 0);
        const seltext: ?[*:0]u8 = if (xsre.selection == c.XA_PRIMARY)
            xsel.primary
        else if (xsre.selection == clipboard)
            xsel.clipboard
        else {
            _ = c.fprintf(c.stderr, "Unhandled clipboard selection 0x%lx\n", xsre.selection);
            return;
        };
        if (seltext) |text| {
            _ = c.XChangeProperty(
                xsre.display,
                xsre.requestor,
                xsre.property,
                xsre.target,
                8,
                c.PropModeReplace,
                text,
                @intCast(c_int, std.mem.len(text)),
            );
            xev.property = xsre.property;
        }
    }
    // all done, send a notification to the listener
    if (c.XSendEvent(
        xsre.display,
        xsre.requestor,
        1,
        0,
        @ptrCast(*c.XEvent, &xev),
    ) == 0)
        _ = c.fprintf(c.stderr, "Error sending SelectionNotify event\n");
}

/// transfers ownership of `str`
fn setsel(str: ?[*:0]u8, t: c.Time) void {
    c.free(xsel.primary);
    xsel.primary = str;

    _ = c.XSetSelectionOwner(xw.dpy, c.XA_PRIMARY, xw.win, t);
    if (c.XGetSelectionOwner(xw.dpy, c.XA_PRIMARY) != xw.win)
        st.selclear();
}
fn xsetsel(str: [*:0]const u8) void {
    setsel(str, c.CurrentTime);
}
fn brelease(e: *c.XEvent) void {
    if (win.mode.any(winmode_mouse) and e.xbutton.state & cfg.forceselmod == 0) {
        mousereport(e);
        return;
    }

    if (e.xbutton.button == c.Button2)
        selpaste(Arg.None)
    else if (e.xbutton.button == c.Button1)
        mousesel(e, 1);
}
fn bmotion(e: *c.XEvent) void {
    if (win.mode.any(winmode_mouse) and e.xbutton.state & cfg.forceselmod == 0) {
        mousereport(e);
        return;
    }
    mousesel(e, 0);
}
fn cresize(width: u32, height: u32) void {
    if (width != 0)
        win.w = width;
    if (height != 0)
        win.h = height;
    const col = std.math.max(1, (win.w - 2 * cfg.borderpx) / win.cw);
    const row = std.math.max(1, (win.h - 2 * cfg.borderpx) / win.ch);

    st.tresize(col, row);
    xresize(col, row);
    st.ttyresize(win.tw, win.th);
}
fn xresize(col: u32, row: u32) void {
    win.tw = col * win.cw;
    win.th = col * win.ch;

    _ = c.XFreePixmap(xw.dpy, xw.buf);
    xw.buf = c.XCreatePixmap(
        xw.dpy,
        xw.win,
        win.w,
        win.h,
        @intCast(c_uint, c._DefaultDepth(xw.dpy, xw.scr)),
    );
    c.XftDrawChange(xw.draw, xw.buf);
    xclear(0, 0, win.w, win.h);

    // resize to new width
    xw.specbuf = @ptrCast([*]c.XftGlyphFontSpec, @alignCast(@alignOf([*]c.XftGlyphFontSpec), st.xrealloc(@ptrCast(*allowzero c_void, xw.specbuf), col * @sizeOf(c.XftGlyphFontSpec))));
}
fn sixd_to_16bit(x: u3) u16 {
    return @intCast(u16, if (x == 0) 0 else 0x3737 + 0x2828 * @intCast(u16, x));
}

fn xloadcolor(i: usize, color_name: ?[*:0]u8, ncolor: *c.XftColor) bool {
    var color: c.XRenderColor = undefined;
    color.alpha = 0xffff;

    var name = color_name orelse blk: {
        if (16 <= i and i <= 255) {
            if (i < 6 * 6 * 6 + 16) {
                const step = i - 16;
                color.red = sixd_to_16bit(@intCast(u3, (step / 36) % 6));
                color.green = sixd_to_16bit(@intCast(u3, (step / 6) % 6));
                color.blue = sixd_to_16bit(@intCast(u3, (step / 1) % 6));
            } else {
                color.red = @intCast(u16, 0x0808 + 0x0a0a * (i - (6 * 6 * 6 + 16)));
                color.green = color.red;
                color.blue = color.red;
            }
            return c.XftColorAllocValue(xw.dpy, xw.vis, xw.cmap, &color, ncolor) != 0;
        } else break :blk cfg.colorname[i];
    };
    return c.XftColorAllocName(xw.dpy, xw.vis, xw.cmap, name, ncolor) != 0;
}

var colors_loaded = false;
fn xloadcols() void {
    if (colors_loaded) {
        for (dc.col) |*cp| c.XftColorFree(xw.dpy, xw.vis, xw.cmap, cp);
    } else {
        dc.col.len = std.math.max(cfg.colorname.len, 256);
        dc.col.ptr = @ptrCast([*]c.XftColor, @alignCast(@alignOf([*]c.XftColor), st.xmalloc(dc.col.len * @sizeOf(c.XftColor))));
    }

    for (dc.col) |*col, i| if (!xloadcolor(i, null, col)) {
        if (cfg.colorname[i]) |name| {
            die("could not allocate color '{}'\n", .{name});
        } else {
            die("could not allocate color {}\n", .{i});
        }
    };
    colors_loaded = true;
}

fn xsetcolorname(x: u32, name: []const u8) u32 {
    if (!(0 <= x and x <= dc.collen)) return false;

    if (!xloadcolor(x, name, &ncolor)) return false;

    c.XftColorFree(xw.dpy, xw.vis, xw.cmap, &dc.col[x]);
    dc.col[x] = ncolor;

    return true;
}

// Absolute coordinates.
fn xclear(x1: u32, y1: u32, x2: u32, y2: u32) void {
    c.XftDrawRect(
        xw.draw,
        &dc.col[if (win.mode.get(.Reverse)) cfg.defaultfg else cfg.defaultbg],
        @intCast(c_int, x1),
        @intCast(c_int, y1),
        x2 - x1,
        y2 - y1,
    );
}
fn xhints() void {
    // another monstrosity because i'm sure XClassHint fields aren't actually mutated
    var class: c.XClassHint = .{
        .res_name = @intToPtr([*c]u8, @ptrToInt(opt_name orelse cfg.termname)),
        .res_class = @intToPtr([*c]u8, @ptrToInt(opt_class orelse cfg.termname)),
    };
    var wm: c.XWMHints = .{
        .flags = c.InputHint,
        .input = 1,
        .initial_state = 0,
        .icon_pixmap = 0,
        .icon_window = 0,
        .icon_x = 0,
        .icon_y = 0,
        .icon_mask = 0,
        .window_group = 0,
    };
    var sizeh: *c.XSizeHints = c.XAllocSizeHints().?;
    sizeh.flags = c.PSize | c.PResizeInc | c.PBaseSize | c.PMinSize;
    sizeh.height = @intCast(c_int, win.h);
    sizeh.width = @intCast(c_int, win.w);
    sizeh.height_inc = @intCast(c_int, win.ch);
    sizeh.width_inc = @intCast(c_int, win.cw);
    sizeh.base_height = 2 * cfg.borderpx;
    sizeh.base_width = 2 * cfg.borderpx;
    sizeh.min_height = @intCast(c_int, win.ch) + 2 * cfg.borderpx;
    sizeh.min_width = @intCast(c_int, win.cw) + 2 * cfg.borderpx;
    if (xw.isfixed) {
        sizeh.flags |= c.PMaxSize;
        sizeh.min_width = @intCast(c_int, win.w);
        sizeh.max_width = @intCast(c_int, win.w);
        sizeh.min_height = @intCast(c_int, win.h);
        sizeh.max_height = @intCast(c_int, win.h);
    }
    if (xw.gm & (c.XValue | c.YValue) != 0) {
        sizeh.flags |= c.USPosition | c.PWinGravity;
        sizeh.x = @intCast(c_int, xw.l);
        sizeh.y = @intCast(c_int, xw.t);
        sizeh.win_gravity = xgeommasktogravity(xw.gm);
    }
    c.XSetWMProperties(xw.dpy, xw.win, null, null, null, 0, sizeh, &wm, &class);
    _ = c.XFree(@ptrCast(?*c_void, sizeh));
}
fn xgeommasktogravity(mask: c_int) c_int {
    return switch (mask & (c.XNegative | c.YNegative)) {
        0 => c.NorthWestGravity,
        c.XNegative => c.NorthEastGravity,
        c.YNegative => c.SouthWestGravity,
        else => c.SouthEastGravity,
    };
}
fn xloadfont(f: *Font, pattern: *c.FcPattern) bool {
    var configured = c.FcPatternDuplicate(pattern) orelse return false;
    _ = c.FcConfigSubstitute(null, configured, .FcMatchPattern);
    c.XftDefaultSubstitute(xw.dpy, xw.scr, configured);
    var result: c.FcResult = undefined;
    var font_match = c.FcFontMatch(null, configured, &result) orelse {
        c.FcPatternDestroy(configured);
        return false;
    };
    f.match = c.XftFontOpenPattern(xw.dpy, font_match) orelse {
        c.FcPatternDestroy(configured);
        c.FcPatternDestroy(font_match);
        return false;
    };
    var wantattr: c_int = undefined;
    var haveattr: c_int = undefined;
    if (c.XftPatternGetInteger(pattern, "slant", 0, &wantattr) == .FcResultMatch) {
        // Check if xft was unable to find a font with the appropriate
        // slant but gave us one anyway. Try to mitigate.
        if (c.XftPatternGetInteger(f.match.pattern, "slant", 0, &haveattr) != .FcResultMatch or haveattr < wantattr) {
            f.badslant = 1;
            _ = c.fputs("font slant does not match\n", c.stderr);
        }
    }
    if (c.XftPatternGetInteger(pattern, "weight", 0, &wantattr) == .FcResultMatch) {
        if (c.XftPatternGetInteger(f.match.pattern, "weight", 0, &haveattr) != .FcResultMatch or haveattr != wantattr) {
            f.badweight = 1;
            _ = c.fputs("font weight does not match\n", c.stderr);
        }
    }
    var extents: c.XGlyphInfo = undefined;
    c.XftTextExtentsUtf8(
        xw.dpy,
        f.match,
        @ptrCast([*]const c.FcChar8, &cfg.ascii_printable),
        cfg.ascii_printable.len,
        &extents,
    );
    f.set = null;
    f.pattern = configured;

    f.ascent = @intCast(u32, f.match.ascent);
    f.descent = @intCast(u32, f.match.descent);
    f.lbearing = 0;
    f.rbearing = @intCast(u16, f.match.max_advance_width);

    f.height = f.ascent + f.descent;
    f.width = @intCast(u32, st.divceil(extents.xOff, cfg.ascii_printable.len));

    return true;
}

fn xloadfonts(fontstr: [*:0]const u8, fontsize: f64) void {
    var fontval: f64 = undefined;
    const maybe_pattern = if (fontstr[0] == '-')
        c.XftXlfdParse(fontstr, 0, 0)
    else
        c.FcNameParse(@ptrCast([*c]const c.FcChar8, @alignCast(@alignOf(c.FcChar8), fontstr)));
    const pattern = maybe_pattern orelse die("can't open font {}\n", .{fontstr});
    if (fontsize > 1) {
        _ = c.FcPatternDel(pattern, c.FC_PIXEL_SIZE);
        _ = c.FcPatternDel(pattern, c.FC_SIZE);
        _ = c.FcPatternAddDouble(pattern, c.FC_PIXEL_SIZE, fontsize);
        usedfontsize = fontsize;
    } else {
        if (c.FcPatternGetDouble(pattern, c.FC_PIXEL_SIZE, 0, &fontval) == .FcResultMatch) {
            usedfontsize = fontval;
        } else if (c.FcPatternGetDouble(pattern, c.FC_SIZE, 0, &fontval) == .FcResultMatch) {
            usedfontsize = -1;
        } else {
            // Default font size is 12, if none given. This is to
            // have a known usedfontsize value.
            _ = c.FcPatternAddDouble(pattern, c.FC_PIXEL_SIZE, 12);
            usedfontsize = 12;
        }
        defaultfontsize = usedfontsize;
    }
    if (!xloadfont(&dc.font, pattern)) die("can't open font {}\n", .{fontstr});
    if (usedfontsize < 0) {
        _ = c.FcPatternGetDouble(dc.font.match.pattern, c.FC_PIXEL_SIZE, 0, &fontval);
        usedfontsize = fontval;
        if (fontsize == 0) defaultfontsize = fontval;
    }
    // Setting character width and height.
    win.cw = @floatToInt(u32, std.math.ceil(@intToFloat(f64, dc.font.width) * cfg.cwscale));
    win.ch = @floatToInt(u32, std.math.ceil(@intToFloat(f64, dc.font.height) * cfg.chscale));
    _ = c.FcPatternDel(pattern, c.FC_SLANT);
    _ = c.FcPatternAddInteger(pattern, c.FC_SLANT, c.FC_SLANT_ITALIC);
    if (!xloadfont(&dc.ifont, pattern)) die("can\'t open font {}\n", .{fontstr});

    _ = c.FcPatternDel(pattern, c.FC_WEIGHT);
    _ = c.FcPatternAddInteger(pattern, c.FC_WEIGHT, c.FC_WEIGHT_BOLD);
    if (!xloadfont(&dc.ibfont, pattern)) die("can\'t open font {}\n", .{fontstr});

    _ = c.FcPatternDel(pattern, c.FC_SLANT);
    _ = c.FcPatternAddInteger(pattern, c.FC_SLANT, c.FC_SLANT_ROMAN);
    if (!xloadfont(&dc.bfont, pattern)) die("can\'t open font {}\n", .{fontstr});

    c.FcPatternDestroy(pattern);
}
fn xunloadfont(f: *Font) void {
    c.XftFontClose(xw.dpy, f.match);
    c.FcPatternDestroy(f.pattern);
    if (f.set) |set|
        c.FcFontSetDestroy(set);
}
fn xunloadfonts() void {
    // Free the loaded fonts in the dont cache.
    while (frc.len > 0) {
        c.XftFontClose(xw.dpy, frc[frc.len - 1].font);
        frc.len -= 1;
    }

    xunloadfont(&dc.font);
    xunloadfont(&dc.bfont);
    xunloadfont(&dc.ifont);
    xunloadfont(&dc.ibfont);
}
fn ximopen(dpy: *c.Display) void {
    var destroy: c.XIMCallback = .{
        .client_data = null,
        .callback = ximdestroy,
    };
    xw.xim = c.XOpenIM(xw.dpy, null, null, null);
    if (xw.xim == null) {
        _ = c.XSetLocaleModifiers("@im=local");
        xw.xim = c.XOpenIM(xw.dpy, null, null, null);
        if (xw.xim == null) {
            _ = c.XSetLocaleModifiers("@im=");
            xw.xim = c.XOpenIM(xw.dpy, null, null, null);
            if (xw.xim == null) die("XOpenIM failed. Could not open input device.\n", .{});
        }
    }
    if (c.XSetIMValues(xw.xim, c.XNDestroyCallback, &destroy, null) != null) die("XSetIMValues failed. Could not set input method value.\n", .{});
    xw.xic = c.XCreateIC(
        xw.xim,
        c.XNInputStyle,
        c.XIMPreeditNothing | c.XIMStatusNothing,
        c.XNClientWindow,
        xw.win,
        c.XNFocusWindow,
        xw.win,
        null,
    );
    if (xw.xic == null) die("XCreateIC failed. Could not obtain input method.\n", .{});
}
fn ximinstantiate(dpy: ?*c.Display, client: c.XPointer, call: c.XPointer) callconv(.C) void {
    ximopen(dpy.?);
    _ = c.XUnregisterIMInstantiateCallback(xw.dpy, null, null, null, ximinstantiate, null);
}
fn ximdestroy(xim: c.XIM, client: c.XPointer, call: c.XPointer) callconv(.C) void {
    xw.xim = null;
    _ = c.XRegisterIMInstantiateCallback(xw.dpy, null, null, null, ximinstantiate, null);
}

fn xinit(cols: u32, rows: u32) void {
    xw.dpy = c.XOpenDisplay(null) orelse die("can't open display\n", .{});
    xw.scr = c.XDefaultScreen(xw.dpy);
    xw.vis = c.XDefaultVisual(xw.dpy, xw.scr);

    // font
    if (c.FcInit() == 0) die("could not init fontconfig\n", .{});

    usedfont = opt_font orelse cfg.font;
    xloadfonts(usedfont, 0);

    // colors
    xw.cmap = c.XDefaultColormap(xw.dpy, xw.scr);
    xloadcols();

    // adjust fixed window geometry
    win.w = 2 * cfg.borderpx + cols * win.cw;
    win.h = 2 * cfg.borderpx + rows * win.ch;
    if (xw.gm & c.XNegative != 0)
        xw.l += c._DisplayWidth(xw.dpy, xw.scr) - @intCast(c_int, win.w) - 2;
    if (xw.gm & c.YNegative != 0)
        xw.t += c._DisplayHeight(xw.dpy, xw.scr) - @intCast(c_int, win.h) - 2;

    // Events
    xw.attrs.background_pixel = dc.col[cfg.defaultbg].pixel;
    xw.attrs.border_pixel = dc.col[cfg.defaultbg].pixel;
    xw.attrs.bit_gravity = c.NorthWestGravity;
    xw.attrs.event_mask = c.FocusChangeMask | c.KeyPressMask | c.KeyReleaseMask | c.ExposureMask | c.VisibilityChangeMask | c.StructureNotifyMask | c.ButtonMotionMask | c.ButtonPressMask | c.ButtonReleaseMask;
    xw.attrs.colormap = xw.cmap;

    var parent = if (opt_embed) |embed| @intCast(c_ulong, c.strtol(embed, null, 0)) else c.XRootWindow(xw.dpy, xw.scr);
    xw.win = c.XCreateWindow(xw.dpy, parent, xw.l, xw.t, win.w, win.h, 0, c.XDefaultDepth(xw.dpy, xw.scr), c.InputOutput, xw.vis, c.CWBackPixel | c.CWBorderPixel | c.CWBitGravity | c.CWEventMask | c.CWColormap, &xw.attrs);

    var gcvalues: c.XGCValues = undefined;
    std.mem.set(u8, std.mem.asBytes(&gcvalues), 0);
    gcvalues.graphics_exposures = c.False;
    dc.gc = c.XCreateGC(xw.dpy, parent, c.GCGraphicsExposures, &gcvalues);
    xw.buf = c.XCreatePixmap(xw.dpy, xw.win, win.w, win.h, @intCast(c_uint, c._DefaultDepth(xw.dpy, xw.scr)));
    _ = c.XSetForeground(xw.dpy, dc.gc, dc.col[cfg.defaultbg].pixel);
    _ = c.XFillRectangle(xw.dpy, xw.buf, dc.gc, 0, 0, win.w, win.h);
    // font spec buffer
    xw.specbuf = @ptrCast([*]c.XftGlyphFontSpec, @alignCast(@alignOf([*]c.XftGlyphFontSpec), st.xmalloc(cols * @sizeOf(c.XftGlyphFontSpec))));

    // Xft rendering context
    xw.draw = c.XftDrawCreate(xw.dpy, xw.buf, xw.vis, xw.cmap).?;

    // input methods
    ximopen(xw.dpy);

    // white cursor, black outline
    var cursor = c.XCreateFontCursor(xw.dpy, cfg.mouseshape);
    _ = c.XDefineCursor(xw.dpy, xw.win, cursor);

    var xmousefg: c.XColor = undefined;
    var xmousebg: c.XColor = undefined;
    if (c.XParseColor(xw.dpy, xw.cmap, cfg.colorname[cfg.mousefg], &xmousefg) == 0) {
        xmousefg.red = 0xffff;
        xmousefg.green = 0xffff;
        xmousefg.blue = 0xffff;
    }

    if (c.XParseColor(xw.dpy, xw.cmap, cfg.colorname[cfg.mousebg], &xmousebg) == 0) {
        xmousebg.red = 0x0000;
        xmousebg.green = 0x0000;
        xmousebg.blue = 0x0000;
    }

    _ = c.XRecolorCursor(xw.dpy, cursor, &xmousefg, &xmousebg);

    xw.xembed = c.XInternAtom(xw.dpy, "_XEMBED", c.False);
    xw.wmdeletewin = c.XInternAtom(xw.dpy, "WM_DELETE_WINDOW", c.False);
    xw.netwmname = c.XInternAtom(xw.dpy, "_NET_WM_NAME", c.False);
    _ = c.XSetWMProtocols(xw.dpy, xw.win, &xw.wmdeletewin, 1);

    xw.netwmpid = c.XInternAtom(xw.dpy, "_NET_WM_PID", c.False);
    var thispid = c.getpid();
    _ = c.XChangeProperty(xw.dpy, xw.win, xw.netwmpid, c.XA_CARDINAL, 32, c.PropModeReplace, @ptrCast(*u8, &thispid), 1);

    win.mode = WindowMode.init_with(.{.Numlock});
    resettitle();
    _ = c.XMapWindow(xw.dpy, xw.win);
    xhints();
    _ = c.XSync(xw.dpy, c.False);

    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &xsel.tclick1);
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &xsel.tclick2);
    xsel.primary = null;
    xsel.clipboard = null;
    xsel.xtarget = c.XInternAtom(xw.dpy, "UTF8_STRING", 0);
    if (xsel.xtarget == c.None)
        xsel.xtarget = c.XA_STRING;
}

fn xmakeglyphfontspecs(specs: [*]c.XftGlyphFontSpec, glyphs: *const Glyph, len: usize, x: u32, y: u32) u32 {
    @compileError("TODO xmakeglyphfontspecs");
}
fn xdrawglyphdfontspecs(specs: [*]c.XftGlyphFontSpec, base: Glyph, len: usize, x: u32, y: u32) void {
    @compileError("TODO xdrawglyphdfontspecs");
}
fn xdrawglyph(g: Glyph, x: u32, y: u32) void {
    var spec: c.XftGlyphFontSpec = undefined;
    const numspecs = xmakeglyphfontspecs(&spec, &g, 1, x, y);
    xdrawglyphfontspecs(&spec, g, numspecs, x, y);
}
pub fn xdrawcursor(cx: u32, xy: u32, g: Glyph, ox: u32, oy: u32, og: Glyph) void {
    @compileError("TODO xdrawcursor");
}

fn xsetenv() void {
    // enough for max u64
    var buf: [64]u8 = undefined;
    _ = std.fmt.formatIntBuf(buf[0..], xw.win, 10, false, .{});
    _ = c.setenv("WINDOWID", &buf, 1);
}
fn resettitle() void {
    xsettitle(null);
}
fn xsettitle(p: ?[*:0]const u8) void {
    // this monstrosity is to get rid of the const qualifier for
    // the Xutf8TextListToTextProperty call, but should actually be safe
    var title = @intToPtr([*c]u8, @ptrToInt(p orelse opt_title.?));
    var prop: c.XTextProperty = undefined;
    _ = c.Xutf8TextListToTextProperty(xw.dpy, &title, 1, .XUTF8StringStyle, &prop);
    c.XSetWMName(xw.dpy, xw.win, &prop);
    c.XSetTextProperty(xw.dpy, xw.win, &prop, xw.netwmname);
    _ = c.XFree(@ptrCast(?*c_void, prop.value));
}
pub fn xstartdraw() bool {
    return win.mode.get(.Visible);
}
pub fn xdrawline(line: st.Line, x1: u32, y1: u32, x2: u32) void {
    var specs = xw.specbuf;
    var numspecs = xmakeglyphfontspecs(specs, &line[x1], x2 - x1, x1, y1);
    var base: Glyph = undefined;
    var i: u32 = 0;
    var ox: u32 = 0;
    var x = x1;
    while (x < x2 and i < numspecs) : (x += 1) {
        var new = line[x];
        if (new.mode.bits == st.Attr.singleton(.WDummy).bits) continue;
        if (st.selected(x, y1))
            new.mode.toggle(.Reverse);
        if (i > 0 and st.ATTRCMP(base, new)) {
            xdrawglyphdfontspecs(specs, base, i, ox, y1);
            specs += i;
            numspecs -= i;
            i = 0;
        }
        if (i == 0) {
            ox = x;
            base = new;
        }
        i += 1;
    }
    if (i > 0)
        xdrawglyphdfontspecs(specs, base, i, ox, y1);
}
pub fn xfinishdraw() void {
    _ = c.XCopyArea(
        xw.dpy,
        xw.buf,
        xw.win,
        dc.gc,
        0,
        0,
        win.w,
        win.h,
        0,
        0,
    );
    _ = c.XSetForeground(
        xw.dpy,
        dc.gc,
        dc.col[if (win.mode.get(.Reverse)) cfg.defaultfg else cfg.defaultbg].pixel,
    );
}
pub fn xximspot(x: u32, y: u32) void {
    const spot: c.XPoint = .{
        .x = @intCast(c_short, cfg.borderpx + x * win.cw),
        .y = @intCast(c_short, cfg.borderpx + (y + 1) * win.ch),
    };
    const attr = c.XVaCreateNestedList(0, c.XNSpotLocation, &spot, null);

    _ = c.XSetICValues(xw.xic, c.XNPreeditAttributes, attr, null);
    _ = c.XFree(attr);
}
fn expose(ev: *c.XEvent) void {
    st.redraw();
}
fn visibility(ev: *c.XEvent) void {
    var e = &ev.xvisibility;
    win.mode.set(.Visible, e.state != c.VisibilityFullyObscured);
}
fn unmap(ev: *c.XEvent) void {
    win.mode.set(.Visible, false);
}
fn xsetpointermotion(set: bool) void {
    st.MODBIT(xw.attrs.event_mask, set, c.PointerMotionMask);
    _ = c.XChangeWindowAttributes(xw.dpy, xw.win, c.CWEventMask, &xw.attrs);
}
fn xsetmode(set: bool, flags: WindowMode) void {
    const old_mode = win.mode;
    win.mode.setAll(flags, set);
    if (win.mode.get(.Reverse) != old_mode.get(.Reverse))
        redraw();
}
fn xsetcursor(cursor: u32) bool {
    const cur = if (cursor != 0) cursor else 1;
    if (!(0 <= cur and cur <= 6)) return false;
    win.cursor = cur;
    return true;
}
fn xseturgency(add: bool) void {
    var h = @as(?*c.XWMHints, c.XGetWMHints(xw.dpy, xw.win)) orelse unreachable;

    st.MODBIT(&h.flags, add, c.XUrgencyHint);
    _ = c.XSetWMHints(xw.dpy, xw.win, h);
    _ = c.XFree(h);
}
fn xbell() void {
    if (!win.mode.get(.Focused))
        xseturgency(true);
    if (cfg.bellvolume != 0)
        _ = c.XkbBell(xw.dpy, xw.win, cfg.bellvolume, @as(c.Atom, null));
}
fn focus(ev: *c.XEvent) void {
    var e = &ev.xfocus;
    if (e.mode == c.NotifyGrab) return;
    if (ev.@"type" == c.FocusIn) {
        c.XSetICFocus(xw.xic);
        win.mode.set(.Focused, true);
        xseturgency(false);
        if (win.mode.get(.Focus))
            st.ttywrite("\x1b[I", false);
    } else {
        c.XUnsetICFocus(xw.xic);
        win.mode.set(.Focused, false);
        if (win.mode.get(.Focus))
            st.ttywrite("\x1b[O", false);
    }
}
fn match(mask: u32, state: u32) bool {
    return mask == XK_ANY_MOD or mask == (state & ~cfg.ignoremod);
}
fn kmap(k: c.KeySym, state: u32) ?[*:0]const u8 {
    for (cfg.mappedkeys) |mk| {
        if (mk == k) break;
    } else {
        if ((k & 0xFFFF) < 0xFD00)
            return null;
    }

    for (cfg.key) |kp| {
        if (kp.k != k)
            continue;

        if (!match(kp.mask, state))
            continue;

        if (if (win.mode.get(.AppKeypad)) kp.appkey < 0 else kp.appkey > 0)
            continue;
        if (win.mode.get(.Numlock) and kp.appkey == 2)
            continue;

        if (if (win.mode.get(.AppCursor)) kp.appcursor < 0 else kp.appcursor > 0)
            continue;

        return kp.s;
    }

    return null;
}
fn kpress(ev: *c.XEvent) void {
    var e = &ev.xkey;
    var ksym: c.KeySym = undefined;
    var buf: [32]u8 = undefined;
    var status: c_int = undefined;

    if (win.mode.get(.KeyboardLock)) return;

    var len = @intCast(usize, c.XmbLookupString(xw.xic, e, &buf, @sizeOf([32]u8), &ksym, &status));
    // 1. shortcuts
    for (cfg.shortcuts) |bp| {
        if ((ksym == bp.keysym) and match(bp.mod, e.state)) {
            bp.func(&bp.arg);
            return;
        }
    }

    // 2. custom keys from config.h
    if (kmap(ksym, e.state)) |customkey| {
        st.ttywrite(std.mem.span(customkey), true);
        return;
    }

    // 3. composed string from input method
    if (len == 0) return;
    if (len == 1 and e.state & c.Mod1Mask != 0) {
        if (win.mode.get(.@"8Bit")) {
            if (buf[0] < 127) {
                var ch: st.Rune = buf[0] | 0x80;
                len = st.utf8encode(ch, @ptrCast([*:0]u8, &buf));
            }
        } else {
            buf[1] = buf[0];
            buf[0] = '\x1b';
            len = 2;
        }
    }
    st.ttywrite(buf[0..len], true);
}
fn cmessage(e: *c.XEvent) void {
    // See xembed specs
    //  http://standards.freedesktop.org/xembed-spec/xembed-spec-latest.html
    if (e.xclient.message_type == xw.xembed and e.xclient.format == 32) {
        if (e.xclient.data.l[1] == XEMBED_FOCUS_IN) {
            win.mode.set(.Focused, true);
            xseturgency(false);
        } else if (e.xclient.data.l[1] == XEMBED_FOCUS_OUT) {
            win.mode.set(.Focused, false);
        }
    } else if (e.xclient.data.l[0] == xw.wmdeletewin) {
        st.ttyhangup();
        std.os.exit(0);
    }
}
fn resize(e: *c.XEvent) void {
    if (e.xconfigure.width == win.w and e.xconfigure.height == win.h) return;
    cresize(@intCast(u32, e.xconfigure.width), @intCast(u32, e.xconfigure.height));
}
fn run() void {
    var xfd = c.XConnectionNumber(xw.dpy);

    var w: u32 = undefined;
    var h: u32 = undefined;
    var ev: c.XEvent = undefined;

    // Waiting for window mapping
    while (true) {
        _ = c.XNextEvent(xw.dpy, &ev);
        // This XFilterEvent call is required because of XOpenIM. It
        // does filter out the key event and some client message for
        // the input method too.
        if (c.XFilterEvent(&ev, c.None) != 0) continue;
        if (ev.@"type" == c.ConfigureNotify) {
            w = @intCast(u32, ev.xconfigure.width);
            h = @intCast(u32, ev.xconfigure.height);
        }
        if (ev.@"type" == c.MapNotify) break;
    }

    var ttyfd = st.ttynew(opt_line, cfg.shell, opt_io, opt_cmd);
    cresize(w, h);

    var last: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &last);
    var lastblink = last;
    var xev: u32 = cfg.actionfps;
    while (true) {
        var rfd: c.fd_set = undefined;
        c._FD_ZERO(&rfd);
        c._FD_SET(ttyfd, &rfd);
        c._FD_SET(xfd, &rfd);

        var tv: ?*c.struct_timespec = null;
        if (c.pselect(std.math.max(xfd, ttyfd) + 1, &rfd, null, null, tv, null) < 0) {
            if (std.c._errno().* == c.EINTR) continue;
            die("select falied: {}\n", .{c.strerror(std.c._errno().*)});
        }
        var blinkset: bool = undefined;
        if (c._FD_ISSET(ttyfd, &rfd)) {
            _ = st.ttyread();
            if (cfg.blinktimeout != 0) {
                blinkset = st.tattrset(.Blink);
                if (blinkset) win.mode.set(.Blink, false);
            }
        }

        if (c._FD_ISSET(xfd, &rfd))
            xev = cfg.actionfps;

        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
        var drawtimeout: c.struct_timespec = .{
            .tv_sec = 0,
            .tv_nsec = @divTrunc(1000 * 1_000_000, cfg.xfps),
        };
        tv = &drawtimeout;

        var dodraw = false;
        if (cfg.blinktimeout != 0 and st.TIMEDIFF(now, lastblink) > cfg.blinktimeout) {
            st.tsetdirtattr(.Blink);
            win.mode.toggle(.Blink);
            lastblink = now;
            dodraw = true;
        }
        var deltatime = st.TIMEDIFF(now, last);
        if (deltatime > @divTrunc(1000, @as(u32, if (xev != 0) cfg.xfps else cfg.actionfps))) {
            dodraw = true;
            last = now;
        }

        if (dodraw) {
            while (c.XPending(xw.dpy) != 0) {
                _ = c.XNextEvent(xw.dpy, &ev);
                if (c.XFilterEvent(&ev, c.None) != 0) continue;
                if (handler[@intCast(usize, ev.@"type")]) |handlerfn|
                    handlerfn(&ev);
            }

            st.draw();
            _ = c.XFlush(xw.dpy);

            if (xev != 0 and !c._FD_ISSET(xfd, &rfd)) xev -= 1;
            if (!c._FD_ISSET(ttyfd, &rfd) and !c._FD_ISSET(xfd, &rfd)) {
                if (blinkset) {
                    drawtimeout.tv_nsec = if (st.TIMEDIFF(now, lastblink) > cfg.blinktimeout)
                        1000
                    else
                        1_000_000 * (cfg.blinktimeout - st.TIMEDIFF(now, lastblink));
                    drawtimeout.tv_sec = @divTrunc(drawtimeout.tv_nsec, 1_000_000_000);
                    drawtimeout.tv_nsec = @mod(drawtimeout.tv_nsec, 1_000_000_000);
                } else {
                    tv = null;
                }
            }
        }
    }
}

const cmdline_params = comptime blk: {
    @setEvalBranchQuota(10_000);
    break :blk [_]clap.Param(clap.Help){
        clap.parseParam("-a                  Disable  alternate screens in terminal") catch unreachable,
        clap.parseParam("-c <class>          Defines the window class (default $TERM)") catch unreachable,
        clap.parseParam("-f <font>           xx") catch unreachable,
        clap.parseParam("-g <geometry>       xx") catch unreachable,
        clap.parseParam("-i                  xx") catch unreachable,
        clap.parseParam("-n <nome>           xx") catch unreachable,
        clap.parseParam("-o <iofile>         xx") catch unreachable,
        clap.parseParam("-T <title>          xx") catch unreachable,
        clap.parseParam("-t <title>          xx") catch unreachable,
        clap.parseParam("-w <windowid>       xx") catch unreachable,
        clap.parseParam("-l <line>           xx") catch unreachable,
        clap.parseParam("-v                  xx") catch unreachable,
        // clap.parseParam("-e <command> [args] xx") catch unreachable,
    };
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = &arena.allocator;
    var args = try clap.parse(clap.Help, cmdline_params[0..], std.heap.page_allocator);

    var allowaltscreen = cfg.allowaltscreen;
    var cols: c_uint = cfg.cols;
    var rows: c_uint = cfg.rows;

    var stderr = std.io.getStdErr().writer();
    defer args.deinit();

    if (args.flag("-a")) {
        allowaltscreen = false;
    }
    if (args.option("-c")) |class| {
        opt_class = (try alloc.dupeZ(u8, class)).ptr;
    }
    if (args.option("-f")) |font| {
        opt_font = (try alloc.dupeZ(u8, font)).ptr;
    }
    if (args.option("-g")) |geometry| {
        xw.gm = c.XParseGeometry((try alloc.dupeZ(u8, geometry)).ptr, &xw.l, &xw.t, &cols, &rows);
    }
    if (args.flag("-i")) {
        xw.isfixed = true;
    }
    if (args.option("-n")) |name| {
        opt_name = (try alloc.dupeZ(u8, name)).ptr;
    }
    if (args.option("-o")) |io| {
        opt_io = (try alloc.dupeZ(u8, io)).ptr;
    }
    if (args.option("-l")) |line| {
        opt_line = (try alloc.dupeZ(u8, line)).ptr;
    }
    if (args.option("-T")) |title| {
        opt_title = (try alloc.dupeZ(u8, title)).ptr;
    }
    if (args.option("-t")) |title| {
        opt_title = (try alloc.dupeZ(u8, title)).ptr;
    }
    if (args.option("-w")) |embed| {
        opt_embed = (try alloc.dupeZ(u8, embed)).ptr;
    }
    if (args.flag("-v")) {
        const exe_name = args.positionals()[0];
        die("{} " ++ program_version ++ "\n", .{exe_name});
    }
    // TODO handle -e !!!
    // if (args.option("-e")) |cmd| {
    //     opt_cmd = ...
    // }

    if (opt_title == null) {
        opt_title = if (opt_line != null)
            program_name
        else if (opt_cmd) |cmd| cmd[0].? else program_name;
    }

    _ = c.setlocale(c.LC_CTYPE, "");
    _ = c.XSetLocaleModifiers("");
    cols = std.math.max(cols, 1);
    rows = std.math.max(rows, 1);

    st.tnew(cols, rows);
    xinit(cols, rows);
    xsetenv();
    st.selinit();
    run();

    return;
}
