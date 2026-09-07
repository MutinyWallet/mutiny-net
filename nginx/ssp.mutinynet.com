# Per-IP limits. nginx.conf applies realip at http level, so $binary_remote_addr
# is the real client address.
limit_req_zone $binary_remote_addr zone=ssp_req:10m rate=10r/s;
limit_conn_zone $binary_remote_addr zone=ssp_conn:10m;

server {
    server_name ssp.mutinynet.com;

    limit_req_status 429;
    limit_conn_status 429;
    limit_conn ssp_conn 20;

    # Self-hosted Spark Service Provider (GraphQL over HTTPS)
    location / {
        limit_req zone=ssp_req burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 300;
        proxy_send_timeout 300;
        # GraphQL requests are small; do not hold slow bodies open.
        client_body_timeout 30;
        client_max_body_size 1m;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = ssp.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name ssp.mutinynet.com;
    return 404; # managed by Certbot
}
