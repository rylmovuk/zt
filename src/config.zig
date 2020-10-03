usingnamespace @import("c.zig");
usingnamespace @import("main.zig");
const st = @import("st.zig");
const sendbreak = st.sendbreak;
const toggleprinter = st.toggleprinter;
const printscreen = st.printscreen;
const printsel = st.printsel;

pub const font = "Liberation Mono:pixelsize=12:antialias=true:autohint=true";
pub const borderpx = 2;

pub const shell = "/bin/sh";
pub const utmp = null;
pub const stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";

pub const vtiden = "\x1b[?6c";

pub const cwscale = 1.0;
pub const chscale = 1.0;

pub const worddelimiters = [_]u16{' '};

pub const doubleclicktimeout = 300;
pub const tripleclicktimeout = 600;

pub const allowaltscreen = true;

pub const xfps = 120;
pub const actionfps = 30;

pub const blinktimeout = 800;

pub const cursorthickness = 2;

pub const bellvolume = 0;

pub const termname = "st-256color";

pub const tabspaces = 8;

pub const colorname = [_]?[*:0]const u8{
    // 8 normal colors
    "black",
    "red3",
    "green3",
    "yellow3",
    "blue2",
    "magenta3",
    "cyan3",
    "gray90",

    // 8 bright colors
    "gray50",
    "red",
    "green",
    "yellow",
    "#5c5cff",
    "magenta",
    "cyan",
    "white",
} ++ [_]?[*:0]const u8{null} ** 240 ++ [_]?[*:0]const u8{
    "#cccccc",
    "#555555",
};

pub const defaultfg = 7;
pub const defaultbg = 0;
pub const defaultcs = 256;
pub const defaultrcs = 257;

pub const cursorshape = 2;

pub const cols = 80;
pub const rows = 24;

pub const mouseshape = XC_xterm;
pub const mousefg = 7;
pub const mousebg = 0;

pub const defaultattr = 11;

const MS = MouseShortcut.init;
pub const mshortcuts = [_]MouseShortcut{
    MS(Button4, XK_ANY_MOD, "\x19"),
    MS(Button5, XK_ANY_MOD, "\x05"),
};

const MODKEY = Mod1Mask;
const TERMMOD = ControlMask | ShiftMask;

const S = Shortcut.init;
// zig fmt: off
pub const shortcuts = [_]Shortcut{
    S(XK_ANY_MOD,       XK_Break,     sendbreak,       .{ .i = 0 }),
    S(ControlMask,      XK_Print,     toggleprinter,   .{ .i = 0 }),
    S(ShiftMask,        XK_Print,     printscreen,     .{ .i = 0 }),
    S(XK_ANY_MOD,       XK_Print,     printsel,        .{ .i = 0 }),
    S(TERMMOD,          XK_Prior,     zoom,            .{ .f = 1 }),
    S(TERMMOD,          XK_Next,      zoom,            .{ .f = -1 }),
    S(TERMMOD,          XK_Home,      zoomreset,       .{ .f = 0 }),
    S(TERMMOD,          XK_C,         clipcopy,        .{ .i = 0 }),
    S(TERMMOD,          XK_V,         clippaste,       .{ .i = 0 }),
    S(TERMMOD,          XK_Y,         selpaste,        .{ .i = 0 }),
    S(ShiftMask,        XK_Insert,    selpaste,        .{ .i = 0 }),
    S(TERMMOD,          XK_Num_Lock,  numlock,         .{ .i = 0 }),
};
// zig fmt: on

pub const mappedkeys = [_]KeySym{@bitCast(u16, @as(i16, -1))};

pub const ignoremod = Mod2Mask | XK_SWITCH_MOD;

pub const forceselmod = ShiftMask;

const K = Key.init;
// zig fmt: off
pub const key = [_]Key{
    K(XK_KP_Home,       ShiftMask,                  "\x1b[2J",      0,  -1  ),
    K(XK_KP_Home,       ShiftMask,                  "\x1b[1;2H",    0,   1  ),
    K(XK_KP_Home,       XK_ANY_MOD,                 "\x1b[H",       0,  -1  ),
    K(XK_KP_Home,       XK_ANY_MOD,                 "\x1b[1~",      0,   1  ),
    K(XK_KP_Up,         XK_ANY_MOD,                 "\x1bOx",       1,   0  ),
    K(XK_KP_Up,         XK_ANY_MOD,                 "\x1b[A",       0,  -1  ),
    K(XK_KP_Up,         XK_ANY_MOD,                 "\x1bOA",       0,   1  ),
    K(XK_KP_Down,       XK_ANY_MOD,                 "\x1bOr",       1,   0  ),
    K(XK_KP_Down,       XK_ANY_MOD,                 "\x1b[B",       0,  -1  ),
    K(XK_KP_Down,       XK_ANY_MOD,                 "\x1bOB",       0,   1  ),
    K(XK_KP_Left,       XK_ANY_MOD,                 "\x1bOt",       1,   0  ),
    K(XK_KP_Left,       XK_ANY_MOD,                 "\x1b[D",       0,  -1  ),
    K(XK_KP_Left,       XK_ANY_MOD,                 "\x1bOD",       0,   1  ),
    K(XK_KP_Right,      XK_ANY_MOD,                 "\x1bOv",       1,   0  ),
    K(XK_KP_Right,      XK_ANY_MOD,                 "\x1b[C",       0,  -1  ),
    K(XK_KP_Right,      XK_ANY_MOD,                 "\x1bOC",       0,   1  ),
    K(XK_KP_Prior,      ShiftMask,                  "\x1b[5;2~",    0,   0  ),
    K(XK_KP_Prior,      XK_ANY_MOD,                 "\x1b[5~",      0,   0  ),
    K(XK_KP_Begin,      XK_ANY_MOD,                 "\x1b[E",       0,   0  ),
    K(XK_KP_End,        ControlMask,                "\x1b[J",      -1,   0  ),
    K(XK_KP_End,        ControlMask,                "\x1b[1;5F",    1,   0  ),
    K(XK_KP_End,        ShiftMask,                  "\x1b[K",      -1,   0  ),
    K(XK_KP_End,        ShiftMask,                  "\x1b[1;2F",    1,   0  ),
    K(XK_KP_End,        XK_ANY_MOD,                 "\x1b[4~",      0,   0  ),
    K(XK_KP_Next,       ShiftMask,                  "\x1b[6;2~",    0,   0  ),
    K(XK_KP_Next,       XK_ANY_MOD,                 "\x1b[6~",      0,   0  ),
    K(XK_KP_Insert,     ShiftMask,                  "\x1b[2;2~",    1,   0  ),
    K(XK_KP_Insert,     ShiftMask,                  "\x1b[4l",     -1,   0  ),
    K(XK_KP_Insert,     ControlMask,                "\x1b[L",      -1,   0  ),
    K(XK_KP_Insert,     ControlMask,                "\x1b[2;5~",    1,   0  ),
    K(XK_KP_Insert,     XK_ANY_MOD,                 "\x1b[4h",     -1,   0  ),
    K(XK_KP_Insert,     XK_ANY_MOD,                 "\x1b[2~",      1,   0  ),
    K(XK_KP_Delete,     ControlMask,                "\x1b[M",      -1,   0  ),
    K(XK_KP_Delete,     ControlMask,                "\x1b[3;5~",    1,   0  ),
    K(XK_KP_Delete,     ShiftMask,                  "\x1b[2K",     -1,   0  ),
    K(XK_KP_Delete,     ShiftMask,                  "\x1b[3;2~",    1,   0  ),
    K(XK_KP_Delete,     XK_ANY_MOD,                 "\x1b[P",      -1,   0  ),
    K(XK_KP_Delete,     XK_ANY_MOD,                 "\x1b[3~",      1,   0  ),
    K(XK_KP_Multiply,   XK_ANY_MOD,                 "\x1bOj",       2,   0  ),
    K(XK_KP_Add,        XK_ANY_MOD,                 "\x1bOk",       2,   0  ),
    K(XK_KP_Enter,      XK_ANY_MOD,                 "\x1bOM",       2,   0  ),
    K(XK_KP_Enter,      XK_ANY_MOD,                 "\r",          -1,   0  ),
    K(XK_KP_Subtract,   XK_ANY_MOD,                 "\x1bOm",       2,   0  ),
    K(XK_KP_Decimal,    XK_ANY_MOD,                 "\x1bOn",       2,   0  ),
    K(XK_KP_Divide,     XK_ANY_MOD,                 "\x1bOo",       2,   0  ),
    K(XK_KP_0,          XK_ANY_MOD,                 "\x1bOp",       2,   0  ),
    K(XK_KP_1,          XK_ANY_MOD,                 "\x1bOq",       2,   0  ),
    K(XK_KP_2,          XK_ANY_MOD,                 "\x1bOr",       2,   0  ),
    K(XK_KP_3,          XK_ANY_MOD,                 "\x1bOs",       2,   0  ),
    K(XK_KP_4,          XK_ANY_MOD,                 "\x1bOt",       2,   0  ),
    K(XK_KP_5,          XK_ANY_MOD,                 "\x1bOu",       2,   0  ),
    K(XK_KP_6,          XK_ANY_MOD,                 "\x1bOv",       2,   0  ),
    K(XK_KP_7,          XK_ANY_MOD,                 "\x1bOw",       2,   0  ),
    K(XK_KP_8,          XK_ANY_MOD,                 "\x1bOx",       2,   0  ),
    K(XK_KP_9,          XK_ANY_MOD,                 "\x1bOy",       2,   0  ),
    K(XK_Up,            ShiftMask,                  "\x1b[1;2A",    0,   0  ),
    K(XK_Up,            Mod1Mask,                   "\x1b[1;3A",    0,   0  ),
    K(XK_Up,            ShiftMask | Mod1Mask,       "\x1b[1;4A",    0,   0  ),
    K(XK_Up,            ControlMask,                "\x1b[1;5A",    0,   0  ),
    K(XK_Up,            ShiftMask | ControlMask,    "\x1b[1;6A",    0,   0  ),
    K(XK_Up,            ControlMask | Mod1Mask,     "\x1b[1;7A",    0,   0  ),
    K(XK_Up,            ShiftMask|ControlMask|Mod1Mask,"\x1b[1;8A", 0,   0  ),
    K(XK_Up,            XK_ANY_MOD,                 "\x1b[A",       0,  -1  ),
    K(XK_Up,            XK_ANY_MOD,                 "\x1bOA",       0,   1  ),
    K(XK_Down,          ShiftMask,                  "\x1b[1;2B",    0,   0  ),
    K(XK_Down,          Mod1Mask,                   "\x1b[1;3B",    0,   0  ),
    K(XK_Down,          ShiftMask | Mod1Mask,       "\x1b[1;4B",    0,   0  ),
    K(XK_Down,          ControlMask,                "\x1b[1;5B",    0,   0  ),
    K(XK_Down,          ShiftMask | ControlMask,    "\x1b[1;6B",    0,   0  ),
    K(XK_Down,          ControlMask | Mod1Mask,     "\x1b[1;7B",    0,   0  ),
    K(XK_Down,          ShiftMask|ControlMask|Mod1Mask,"\x1b[1;8B", 0,   0  ),
    K(XK_Down,          XK_ANY_MOD,                 "\x1b[B",       0,  -1  ),
    K(XK_Down,          XK_ANY_MOD,                 "\x1bOB",       0,   1  ),
    K(XK_Left,          ShiftMask,                  "\x1b[1;2D",    0,   0  ),
    K(XK_Left,          Mod1Mask,                   "\x1b[1;3D",    0,   0  ),
    K(XK_Left,          ShiftMask | Mod1Mask,       "\x1b[1;4D",    0,   0  ),
    K(XK_Left,          ControlMask,                "\x1b[1;5D",    0,   0  ),
    K(XK_Left,          ShiftMask | ControlMask,    "\x1b[1;6D",    0,   0  ),
    K(XK_Left,          ControlMask | Mod1Mask,     "\x1b[1;7D",    0,   0  ),
    K(XK_Left,          ShiftMask|ControlMask|Mod1Mask,"\x1b[1;8D", 0,   0  ),
    K(XK_Left,          XK_ANY_MOD,                 "\x1b[D",       0,  -1  ),
    K(XK_Left,          XK_ANY_MOD,                 "\x1bOD",       0,   1  ),
    K(XK_Right,         ShiftMask,                  "\x1b[1;2C",    0,   0  ),
    K(XK_Right,         Mod1Mask,                   "\x1b[1;3C",    0,   0  ),
    K(XK_Right,         ShiftMask | Mod1Mask,       "\x1b[1;4C",    0,   0  ),
    K(XK_Right,         ControlMask,                "\x1b[1;5C",    0,   0  ),
    K(XK_Right,         ShiftMask | ControlMask,    "\x1b[1;6C",    0,   0  ),
    K(XK_Right,         ControlMask | Mod1Mask,     "\x1b[1;7C",    0,   0  ),
    K(XK_Right,         ShiftMask|ControlMask|Mod1Mask,"\x1b[1;8C", 0,   0  ),
    K(XK_Right,         XK_ANY_MOD,                 "\x1b[C",       0,  -1  ),
    K(XK_Right,         XK_ANY_MOD,                 "\x1bOC",       0,   1  ),
    K(XK_ISO_Left_Tab,  ShiftMask,                  "\x1b[Z",       0,   0  ),
    K(XK_Return,        Mod1Mask,                   "\x1b\r",       0,   0  ),
    K(XK_Return,        XK_ANY_MOD,                 "\r",           0,   0  ),
    K(XK_Insert,        ShiftMask,                  "\x1b[4l",     -1,   0  ),
    K(XK_Insert,        ShiftMask,                  "\x1b[2;2~",    1,   0  ),
    K(XK_Insert,        ControlMask,                "\x1b[L",      -1,   0  ),
    K(XK_Insert,        ControlMask,                "\x1b[2;5~",    1,   0  ),
    K(XK_Insert,        XK_ANY_MOD,                 "\x1b[4h",     -1,   0  ),
    K(XK_Insert,        XK_ANY_MOD,                 "\x1b[2~",      1,   0  ),
    K(XK_Delete,        ControlMask,                "\x1b[M",      -1,   0  ),
    K(XK_Delete,        ControlMask,                "\x1b[3;5~",    1,   0  ),
    K(XK_Delete,        ShiftMask,                  "\x1b[2K",     -1,   0  ),
    K(XK_Delete,        ShiftMask,                  "\x1b[3;2~",    1,   0  ),
    K(XK_Delete,        XK_ANY_MOD,                 "\x1b[P",      -1,   0  ),
    K(XK_Delete,        XK_ANY_MOD,                 "\x1b[3~",      1,   0  ),
    K(XK_BackSpace,     XK_NO_MOD,                  "\x7f",         0,   0  ),
    K(XK_BackSpace,     Mod1Mask,                   "\x1b\x7f",     0,   0  ),
    K(XK_Home,          ShiftMask,                  "\x1b[2J",      0,  -1  ),
    K(XK_Home,          ShiftMask,                  "\x1b[1;2H",    0,   1  ),
    K(XK_Home,          XK_ANY_MOD,                 "\x1b[H",       0,  -1  ),
    K(XK_Home,          XK_ANY_MOD,                 "\x1b[1~",      0,   1  ),
    K(XK_End,           ControlMask,                "\x1b[J",      -1,   0  ),
    K(XK_End,           ControlMask,                "\x1b[1;5F",    1,   0  ),
    K(XK_End,           ShiftMask,                  "\x1b[K",      -1,   0  ),
    K(XK_End,           ShiftMask,                  "\x1b[1;2F",    1,   0  ),
    K(XK_End,           XK_ANY_MOD,                 "\x1b[4~",      0,   0  ),
    K(XK_Prior,         ControlMask,                "\x1b[5;5~",    0,   0  ),
    K(XK_Prior,         ShiftMask,                  "\x1b[5;2~",    0,   0  ),
    K(XK_Prior,         XK_ANY_MOD,                 "\x1b[5~",      0,   0  ),
    K(XK_Next,          ControlMask,                "\x1b[6;5~",    0,   0  ),
    K(XK_Next,          ShiftMask,                  "\x1b[6;2~",    0,   0  ),
    K(XK_Next,          XK_ANY_MOD,                 "\x1b[6~",      0,   0  ),
    K(XK_F1,            XK_NO_MOD,                  "\x1bOP",       0,   0  ),
    K(XK_F1,            ShiftMask,                  "\x1b[1;2P",    0,   0  ),
    K(XK_F1,            ControlMask,                "\x1b[1;5P",    0,   0  ),
    K(XK_F1,            Mod4Mask,                   "\x1b[1;6P",    0,   0  ),
    K(XK_F1,            Mod1Mask,                   "\x1b[1;3P",    0,   0  ),
    K(XK_F1,            Mod3Mask,                   "\x1b[1;4P",    0,   0  ),
    K(XK_F2,            XK_NO_MOD,                  "\x1bOQ",       0,   0  ),
    K(XK_F2,            ShiftMask,                  "\x1b[1;2Q",    0,   0  ),
    K(XK_F2,            ControlMask,                "\x1b[1;5Q",    0,   0  ),
    K(XK_F2,            Mod4Mask,                   "\x1b[1;6Q",    0,   0  ),
    K(XK_F2,            Mod1Mask,                   "\x1b[1;3Q",    0,   0  ),
    K(XK_F2,            Mod3Mask,                   "\x1b[1;4Q",    0,   0  ),
    K(XK_F3,            XK_NO_MOD,                  "\x1bOR",       0,   0  ),
    K(XK_F3,            ShiftMask,                  "\x1b[1;2R",    0,   0  ),
    K(XK_F3,            ControlMask,                "\x1b[1;5R",    0,   0  ),
    K(XK_F3,            Mod4Mask,                   "\x1b[1;6R",    0,   0  ),
    K(XK_F3,            Mod1Mask,                   "\x1b[1;3R",    0,   0  ),
    K(XK_F3,            Mod3Mask,                   "\x1b[1;4R",    0,   0  ),
    K(XK_F4,            XK_NO_MOD,                  "\x1bOS",       0,   0  ),
    K(XK_F4,            ShiftMask,                  "\x1b[1;2S",    0,   0  ),
    K(XK_F4,            ControlMask,                "\x1b[1;5S",    0,   0  ),
    K(XK_F4,            Mod4Mask,                   "\x1b[1;6S",    0,   0  ),
    K(XK_F4,            Mod1Mask,                   "\x1b[1;3S",    0,   0  ),
    K(XK_F5,            XK_NO_MOD,                  "\x1b[15~",     0,   0  ),
    K(XK_F5,            ShiftMask,                  "\x1b[15;2~",   0,   0  ),
    K(XK_F5,            ControlMask,                "\x1b[15;5~",   0,   0  ),
    K(XK_F5,            Mod4Mask,                   "\x1b[15;6~",   0,   0  ),
    K(XK_F5,            Mod1Mask,                   "\x1b[15;3~",   0,   0  ),
    K(XK_F6,            XK_NO_MOD,                  "\x1b[17~",     0,   0  ),
    K(XK_F6,            ShiftMask,                  "\x1b[17;2~",   0,   0  ),
    K(XK_F6,            ControlMask,                "\x1b[17;5~",   0,   0  ),
    K(XK_F6,            Mod4Mask,                   "\x1b[17;6~",   0,   0  ),
    K(XK_F6,            Mod1Mask,                   "\x1b[17;3~",   0,   0  ),
    K(XK_F7,            XK_NO_MOD,                  "\x1b[18~",     0,   0  ),
    K(XK_F7,            ShiftMask,                  "\x1b[18;2~",   0,   0  ),
    K(XK_F7,            ControlMask,                "\x1b[18;5~",   0,   0  ),
    K(XK_F7,            Mod4Mask,                   "\x1b[18;6~",   0,   0  ),
    K(XK_F7,            Mod1Mask,                   "\x1b[18;3~",   0,   0  ),
    K(XK_F8,            XK_NO_MOD,                  "\x1b[19~",     0,   0  ),
    K(XK_F8,            ShiftMask,                  "\x1b[19;2~",   0,   0  ),
    K(XK_F8,            ControlMask,                "\x1b[19;5~",   0,   0  ),
    K(XK_F8,            Mod4Mask,                   "\x1b[19;6~",   0,   0  ),
    K(XK_F8,            Mod1Mask,                   "\x1b[19;3~",   0,   0  ),
    K(XK_F9,            XK_NO_MOD,                  "\x1b[20~",     0,   0  ),
    K(XK_F9,            ShiftMask,                  "\x1b[20;2~",   0,   0  ),
    K(XK_F9,            ControlMask,                "\x1b[20;5~",   0,   0  ),
    K(XK_F9,            Mod4Mask,                   "\x1b[20;6~",   0,   0  ),
    K(XK_F9,            Mod1Mask,                   "\x1b[20;3~",   0,   0  ),
    K(XK_F10,           XK_NO_MOD,                  "\x1b[21~",     0,   0  ),
    K(XK_F10,           ShiftMask,                  "\x1b[21;2~",   0,   0  ),
    K(XK_F10,           ControlMask,                "\x1b[21;5~",   0,   0  ),
    K(XK_F10,           Mod4Mask,                   "\x1b[21;6~",   0,   0  ),
    K(XK_F10,           Mod1Mask,                   "\x1b[21;3~",   0,   0  ),
    K(XK_F11,           XK_NO_MOD,                  "\x1b[23~",     0,   0  ),
    K(XK_F11,           ShiftMask,                  "\x1b[23;2~",   0,   0  ),
    K(XK_F11,           ControlMask,                "\x1b[23;5~",   0,   0  ),
    K(XK_F11,           Mod4Mask,                   "\x1b[23;6~",   0,   0  ),
    K(XK_F11,           Mod1Mask,                   "\x1b[23;3~",   0,   0  ),
    K(XK_F12,           XK_NO_MOD,                  "\x1b[24~",     0,   0  ),
    K(XK_F12,           ShiftMask,                  "\x1b[24;2~",   0,   0  ),
    K(XK_F12,           ControlMask,                "\x1b[24;5~",   0,   0  ),
    K(XK_F12,           Mod4Mask,                   "\x1b[24;6~",   0,   0  ),
    K(XK_F12,           Mod1Mask,                   "\x1b[24;3~",   0,   0  ),
    K(XK_F13,           XK_NO_MOD,                  "\x1b[1;2P",    0,   0  ),
    K(XK_F14,           XK_NO_MOD,                  "\x1b[1;2Q",    0,   0  ),
    K(XK_F15,           XK_NO_MOD,                  "\x1b[1;2R",    0,   0  ),
    K(XK_F16,           XK_NO_MOD,                  "\x1b[1;2S",    0,   0  ),
    K(XK_F17,           XK_NO_MOD,                  "\x1b[15;2~",   0,   0  ),
    K(XK_F18,           XK_NO_MOD,                  "\x1b[17;2~",   0,   0  ),
    K(XK_F19,           XK_NO_MOD,                  "\x1b[18;2~",   0,   0  ),
    K(XK_F20,           XK_NO_MOD,                  "\x1b[19;2~",   0,   0  ),
    K(XK_F21,           XK_NO_MOD,                  "\x1b[20;2~",   0,   0  ),
    K(XK_F22,           XK_NO_MOD,                  "\x1b[21;2~",   0,   0  ),
    K(XK_F23,           XK_NO_MOD,                  "\x1b[23;2~",   0,   0  ),
    K(XK_F24,           XK_NO_MOD,                  "\x1b[24;2~",   0,   0  ),
    K(XK_F25,           XK_NO_MOD,                  "\x1b[1;5P",    0,   0  ),
    K(XK_F26,           XK_NO_MOD,                  "\x1b[1;5Q",    0,   0  ),
    K(XK_F27,           XK_NO_MOD,                  "\x1b[1;5R",    0,   0  ),
    K(XK_F28,           XK_NO_MOD,                  "\x1b[1;5S",    0,   0  ),
    K(XK_F29,           XK_NO_MOD,                  "\x1b[15;5~",   0,   0  ),
    K(XK_F30,           XK_NO_MOD,                  "\x1b[17;5~",   0,   0  ),
    K(XK_F31,           XK_NO_MOD,                  "\x1b[18;5~",   0,   0  ),
    K(XK_F32,           XK_NO_MOD,                  "\x1b[19;5~",   0,   0  ),
    K(XK_F33,           XK_NO_MOD,                  "\x1b[20;5~",   0,   0  ),
    K(XK_F34,           XK_NO_MOD,                  "\x1b[21;5~",   0,   0  ),
    K(XK_F35,           XK_NO_MOD,                  "\x1b[23;5~",   0,   0  ),
};
// zig fmt: on

pub const selmasks = [_]u32{ 0, 0, Mod1Mask };

pub const ascii_printable =
    \\ !\"#$%&'()*+,-./0123456789:;<=>?"
    \\@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
    \\`abcdefghijklmnopqrstuvwxyz{|}~"
;
