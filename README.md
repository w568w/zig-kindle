# zig-kindle

A project template for running Zig programs on Kindle devices (and other Linux devices with older kernels).

Check out [this gist](https://gist.github.com/w568w/d423ef9e1b473c928d19e7c49e521f8a) for details and original thoughts.

## Overview

Kindle devices run older versions of Linux kernels that don't support newer system calls like `statx`. This project patches the Zig standard library to resolve compatibility issues, enabling Zig programs to run properly on Kindle devices.

The primary logic is in `build.zig` and `kindle.patch`.
