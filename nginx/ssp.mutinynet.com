server {
    server_name ssp.mutinynet.com;

    # Self-hosted Spark Service Provider (GraphQL over HTTPS)
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 300;
        proxy_send_timeout 300;
        client_body_timeout 300;
        client_max_body_size 10M;
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
