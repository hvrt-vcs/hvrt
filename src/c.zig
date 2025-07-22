//! Single namespace/location for including all C header files

pub usingnamespace @cImport({
    @cInclude("sqlite3.h");
    @cInclude("sqlite_transient_workaround.h");

    // Defining this cmacro here is a dirty hack to get pcre2 to build. Fix
    // build.zig so this @cDefine isn't needed here.
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");

    // For parsing arguments.
    // Originally from: https://github.com/attractivechaos/klib/blob/master/ketopt.h
    // Comparison: https://attractivechaos.wordpress.com/2018/08/31/a-survey-of-argument-parsing-libraries-in-c-c/
    // Usage examples: https://attractivechaos.github.io/klib/#Ketopt%3A%20parsing%20command-line%20arguments
    @cInclude("ketopt.h");
});
