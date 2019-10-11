.PHONY: build
build:
	docker build . -t zipstream

.PHONY: run
run: build
	docker run -p 80:80 \
		-v ${PWD}/docker/nginx/conf.d:/etc/nginx/conf.d:ro \
		-v ${PWD}/lua/nginx_lua_zipstream.lua:/usr/local/openresty/lualib/nginx_lua_zipstream.lua:ro \
		-v ${PWD}/fixtures:/files \
		-ti zipstream

.PHONY: check
check:
	luacheck --globals ngx -- lua/nginx_lua_zipstream.lua 
