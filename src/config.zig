const wchar_t = c_int;

// spaces per tab
//
// When you are changing this value, don't forget to adapt the »it« value in
// the st.info and appropriately install the st.info in the environment where
// you use this st version.
//
//	it#$tabspaces,
//
// Secondly make sure your kernel is not expanding tabs. When running `stty
// -a` »tab0« should appear. You can tell the terminal to not expand tabs by
//  running following command:
//
//	stty tabs
//
pub const tabspaces = 8;

pub const worddelimiters = [_:0]wchar_t{' '};

pub const defaultfg = 7;
pub const defaultbg = 0;

pub const vtiden = "\x1b[?6c";

pub const allowaltscreen = true;

pub const utmp: ?[*:0]const u8 = null;

pub const termname = "st-256color";

pub const stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";
