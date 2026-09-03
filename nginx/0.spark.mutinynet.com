server {
    server_name 0.spark.mutinynet.com;

    # gRPC endpoint (main Spark operator API)
    location / {
        grpc_pass grpcs://127.0.0.1:10010;
        grpc_set_header Host $host;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto $scheme;

        # gRPC specific settings
        grpc_read_timeout 300;
        grpc_send_timeout 300;
        client_body_timeout 300;
        client_max_body_size 10M;

        # Enable gRPC error details
        grpc_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }

    listen 443 ssl; # managed by Certbot
    http2 on;  # gRPC requires HTTP/2; without ALPN h2 clients get TLS alert 120
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = 0.spark.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name 0.spark.mutinynet.com;
    return 404; # managed by Certbot
}
