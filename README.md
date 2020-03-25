# lua-nginx-zipstream

Streams zip file containing multiple files for download.

This repository contains a lua module for nginx that works like `mod-zip`. Included is a sample configuration and a demo executed via Docker container.

If you need to send a zip file containing multiple files and you want to create it on-the-fly, this module is for you.

This module, installed into nginx in front of your web application can proxy requests and reply on behalf of your application. This is controlled by a header, which instructs zipstream to create a response. The header is `X-Archive-Files: zip`. In addition to this header your application should emit a list of files as such:

```
<crc32> <size> <url_encoded_path> <path_within_archive>
```

In all honesty, the first two fields are ignored and only included to maintain compatability with `mod_zip`.

This module will the fetch each file and stream a zip archive to the client. It fetches files via HTTP, so you must configure a URL at which the files are available. In most cases this URL would be localhost (the same nginx server). But you could just as easily refer to a different HTTP server where the files reside.

See the [sample config](docker/nginx/conf.d/zipstream.conf) in this repository.

This module requires multiple lua and C dependencies, see the [Dockerfile](Dockerfile) for details.

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

Once running visit http://localhost:8080/zipstream/anything for the demo. You should get a zipfile to download.
