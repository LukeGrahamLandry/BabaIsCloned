# Baba Is Cloned 

A reimplementation of [Baba Is You](https://hempuli.com/baba/). The original game is ~40k lines of lua and the goal of this project is to recreate it with a tiny fraction of that. 

No code/data/assets from the original game are included in this project. However, if you already own the game, this can read thier level format and use thier textures. 

## Design   

Functions that do bit fiddling should not do IO.  

The code makes use of a temperary bump allocator that gets reset every frame. It's kinda like manual generational garbage collection or escape analysis. This make allocations that happen every frame very fast, because they're just incrementing a pointer. However, it means you must be very careful not to hold one of these pointers over a frame boundary as the data will be garbage. 

## Third Party Libraries

These are included as git submodules in the `vendor` directory. Run `submodule update --init --recursive` to make sure you have them. 

- [sokol](https://github.com/floooh/sokol): Platform abstraction for graphics. 
- [zigimg](https://github.com/zigimg/zigimg): Read png files. 

## Build

> Tested with Zig 0.11.0

- [Install Zig](https://ziglang.org/download/)
- `zig build run -Doptimize=ReleaseSafe`
