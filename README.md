# lua-nginx-zipstream
Streams zip file containing multiple files for download.

This repository contains a lua module for nginx that works like `mod-zip`. Included is a sample configuration and a demo executed via Docker container.

## Install development tools

```bash
$ sudo apt install lua5.1
$ sudo apt install lua-check
```

## Commands

```bash
# lints the code
$ make check

# builds the docker image
$ make build

# runs the demo (in container)
$ make run
```

Once running visit http://localhost/zipstream for the demo.
