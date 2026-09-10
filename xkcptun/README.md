# xkcptun

xkcptun is a high-performance C language implementation of kcptun based on KCP protocol and libevent.

## Features

- Written in pure C with high throughput and low memory footprint
- KCP protocol tuning profiles (`fast3`, `fast2`, `fast`, `normal`)
- Reed-Solomon Forward Error Correction (FEC) support
- Loss-driven AIMD congestion control & send pacing
- Multi-instance client and server daemon management via procd
- Full LuCI web UI configuration support
