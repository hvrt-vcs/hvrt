//! Single namespace/location for including all C header files

pub usingnamespace @cImport({
    @cInclude("sqlite3.h");
});
