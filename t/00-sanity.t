use Test::Nginx::Socket::Lua;

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 8083 http2;
        location = /t1 {
            return 200;
        }

        location = /t2 {
            return 200 "hello world";
        }

        location = /t3 {
            http2_chunk_size 256;
            content_by_lua_block {
                local data = {}
                for i = 48, 120 do
                    data[i - 47] = string.char(i)
                end

                for i = 1, 50 do
                    ngx.print(data)
                    ngx.flush(true)
                end
            }
        }

        location = /t4 {
            return 200;
            header_filter_by_lua_block {
                local cookie = {}
                for i = 1, 20000 do
                    cookie[i] = string.char(math.random(48, 97))
                end

                ngx.header["Cookie"] = table.concat(cookie)
            }
        }

        location = /t5 {
            return 200;
            add_header test-header 1;
            add_header test-header 2;
            add_header test-header 3;
        }

        location = /t6 {
            return 200;
            add_header Keep-Alive 100;
        }
    }
EOC

repeat_each(3);
plan tests => repeat_each() * blocks() * 3;
no_long_string();
run_tests();

__DATA__

=== TEST 1: GET request and zero Content-Length 

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t1" },
                { name = ":scheme", value = "http" },
                { name = "accept-encoding", value = "deflate, gzip" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length or length == "0")

                return true
            end

            local on_data_reach = function(ctx, data)
                error("unexpected data")
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 2: GET request with response body

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t2" },
                { name = ":scheme", value = "http" },
                { name = "accept-encoding", value = "deflate, gzip" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length or length == "11")
            end

            local on_data_reach = function(ctx, data)
                assert(data == "hello world")
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 3: POST request with request body

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t1" },
                { name = ":scheme", value = "http" },
                { name = "accept-encoding", value = "deflate, gzip" },
                { name = "content-length", value = "11" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length or length == "0")
            end

            local on_data_reach = function(ctx, data)
                if #data > 0 then
                    error("unexpected DATA frame")
                end
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, "hello world",
                                           on_headers_reach, on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 4: GET request with bulk response body

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t3" },
                { name = ":scheme", value = "http" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length or length == "3650")
            end

            local data_frame_count = 0
            local on_data_reach = function(ctx, data)
                data_frame_count = data_frame_count + 1
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(data_frame_count == 51)

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 5: HEAD request

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "HEAD" },
                { name = ":path", value = "/t1" },
                { name = ":scheme", value = "http" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length or length == "0")
            end

            local on_data_reach = function(ctx, data)
                error("unexpected DATA frame")
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 6: keepalive

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t3" },
                { name = ":scheme", value = "http" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(headers[":status"] == "200")
                local length = headers["content-length"]
                assert(not length)
            end

            local data_length = 0

            local on_data_reach = function(ctx, data)
                data_length = data_length + #data
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083, {pool = "h2"})
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:setkeepalive(nil, 1)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(data_length == 3650)

            ngx.print("OK1")

            client:keepalive("key")

            data_length = 0

            sock = ngx.socket.tcp()
            ok, err = sock:connect("127.0.0.1", 8083, {pool = "h2"})
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local reuse_times = sock:getreusedtimes()
            assert(reuse_times == 1)

            client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
                key = "key",
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            ok, err = client:request(headers, nil, on_headers_reach, on_data_reach)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(data_length == 3650)

            ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            ngx.print("OK2")
        }
    }

--- request
GET /t

--- response_body: OK1OK2
--- no_error_log
[error]



=== TEST 7: large response headers

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t4" },
                { name = ":scheme", value = "http" },
                { name = "accept-encoding", value = "deflate, gzip" },
            }

            local on_headers_reach = function(ctx, headers)
                assert(#headers["cookie"] == 20000)
            end

            local on_data_reach = function(ctx, data)
                if #data > 0 then
                    error("unexpected DATA frame")
                end
            end

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
                preread_size = 1024,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:request(headers, nil, on_headers_reach,
                                           on_data_reach)

            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]


=== TEST 8: duplicate response headers

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t5" },
                { name = ":scheme", value = "http" },
            }

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
                preread_size = 1024,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:acknowledge_settings()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local stream, err = client:send_request(headers)
            if not stream then
                ngx.log(ngx.ERR, err)
                return
            end

            local headers, err = client:read_headers(stream)
            if not headers then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(type(headers["test-header"] == "table"))
            local th = headers["test-header"]

            assert(th[1] == "1")
            assert(th[2] == "2")
            assert(th[3] == "3")

            local ok, err = client:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]



=== TEST 9: peer sent connection specific headers

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local http2 = require "resty.http2"
            local headers = {
                { name = ":authority", value = "test.com" },
                { name = ":method", value = "GET" },
                { name = ":path", value = "/t6" },
                { name = ":scheme", value = "http" },
            }

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 8083)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local client, err = http2.new {
                ctx = sock,
                recv = sock.receive,
                send = sock.send,
                preread_size = 1024,
            }

            if not client then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = client:acknowledge_settings()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local stream, err = client:send_request(headers)
            if not stream then
                ngx.log(ngx.ERR, err)
                return
            end

            local headers, err = client:read_headers(stream)
            if not headers then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(headers["keep-alive"] == nil)

            local ok, err = client:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print("OK")
        }
    }

--- request
GET /t

--- response_body: OK
--- no_error_log
[error]
