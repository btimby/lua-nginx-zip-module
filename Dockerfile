FROM openresty/openresty:alpine-fat

RUN apk add --update-cache git build-base zlib-dev && \
    rm -rf /var/cache/apk/*

RUN luarocks install struct
RUN luarocks install bit32
RUN luarocks install lzlib ZLIB_DIR=/ ZLIB_INCDIR=/usr/include
RUN luarocks install zipwriter
RUN luarocks install lua-resty-httpipe

EXPOSE 80:80
