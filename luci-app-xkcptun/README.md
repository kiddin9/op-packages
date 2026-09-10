# LuCI Support for xkcptun

LuCI Web user interface for configuring and managing `xkcptun` (C language high-performance kcptun) client and server instances.

## Features

- Real-time service status monitoring
- Manage multiple client and server instances
- Configurable KCP performance profiles (`fast3`, `fast2`, `fast`, `normal`, `manual`)
- Advanced tuning: MTU, sndwnd/rcvwnd, Reed-Solomon FEC shards, DSCP, nodelay, interval, fast resend, loss-driven AIMD window adaptation, send pacing, and keepalive/timeout settings.
