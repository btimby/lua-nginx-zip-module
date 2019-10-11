FROM openresty/openresty:centos

RUN yum install -y gcc zlib-devel && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN luarocks install struct
RUN luarocks install bit32
RUN luarocks install lzlib
RUN luarocks install zipwriter

EXPOSE 80:80
