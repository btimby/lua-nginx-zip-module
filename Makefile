.PHONY: build
build:
	docker build . -t zipstream

.PHONY: run
run: build
	docker run -p 80:80 \
		-v ${PWD}/docker/nginx/conf.d:/etc/nginx/conf.d:ro \
		-v ${PWD}/nginx_lua_zipstream:/usr/local/openresty/lualib/nginx_lua_zipstream:ro \
		-v ${PWD}/fixtures:/files \
		-ti zipstream

