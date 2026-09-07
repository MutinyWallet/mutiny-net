# Per-IP limits. nginx.conf applies realip at http level, so $binary_remote_addr
# is the real client address.
limit_req_zone $binary_remote_addr zone=spark1_req:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=spark1_authn:10m rate=5r/s;
limit_conn_zone $binary_remote_addr zone=spark1_conn:10m;

server {
    server_name 1.spark.mutinynet.com;
    set $spark_upstream grpcs://127.0.0.1:10011;

    limit_req_status 429;
    limit_conn_status 429;
    limit_conn spark1_conn 32;
    http2_max_concurrent_streams 32;

    # Deny the SO-to-SO and test-only services. The operator also enforces
    # service_authz (only 10.x peers may call them), but keep the edge rule
    # so a config regression in either layer is not fatal.
    location ~ ^/(mock\.MockService|spark_internal\.SparkInternalService|spark_token\.SparkTokenInternalService|dkg\.DKGService|gossip\.GossipService)/ {
        return 404;
    }

    # Challenge RPCs are anonymous and cache state per call. Keep them tight.
    location ~ ^/spark_authn\.SparkAuthnService/ {
        limit_req zone=spark1_authn burst=10 nodelay;
        include /root/mutiny-net/nginx/spark-grpc-proxy.conf;
    }

    # gRPC endpoint (main Spark operator API)
    location / {
        limit_req zone=spark1_req burst=60 nodelay;
        include /root/mutiny-net/nginx/spark-grpc-proxy.conf;
    }

    listen 443 ssl; # managed by Certbot
    http2 on;  # gRPC requires HTTP/2; without ALPN h2 clients get TLS alert 120
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = 1.spark.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name 1.spark.mutinynet.com;
    return 404; # managed by Certbot
}
