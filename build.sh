#!/bin/sh
zig build-exe src/main.zig -femit-bin=./zig-out/bin/hvrt --cache-dir ./zig-cache --global-cache-dir ~/.cache/zig --name hvrt -L /usr/lib/x86_64-linux-gnu -I /usr/include
