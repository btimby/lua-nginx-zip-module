FROM openresty/openresty:1.15.8.3-alpine-fat

RUN apk add --update-cache git build-base zlib-dev && \
    rm -rf /var/cache/apk/*

RUN luarocks install struct 1.4-1
RUN luarocks install bit32 5.3.0-1
RUN luarocks install lzlib 0.4.1.53-1 ZLIB_DIR=/ ZLIB_INCDIR=/usr/include
RUN luarocks install zipwriter 0.1.5-1
RUN luarocks install lua-resty-httpipe 0.05-1

EXPOSE 80:80
