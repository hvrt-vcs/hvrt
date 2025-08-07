//! Single namespace/location for including all C header files

pub usingnamespace @cImport({
    @cInclude("sqlite3.h");
    @cInclude("sqlite_transient_workaround.h");

    // Defining this cmacro here is a dirty hack to get pcre2 to build. Fix
    // build.zig so this @cDefine isn't needed here.
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});
