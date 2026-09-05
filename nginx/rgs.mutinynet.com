limit_conn_zone $binary_remote_addr zone=rgs_clients:10m;
limit_req_zone $binary_remote_addr zone=rgs_snapshots:10m rate=5r/s;

server {
	server_name rgs.mutinynet.com;
	limit_conn rgs_clients 20;
	limit_conn_status 429;
	limit_req_status 429;
    root /var/www/rgs;

	location / {
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Max-Age' 1728000 always;
            add_header 'Content-Type' 'text/plain; charset=utf-8' always;
            add_header 'Content-Length' 0 always;
            return 204;
        }
        if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }
        if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }

        include /root/mutiny-net/nginx/hsts.conf;
        index index.html; # Default files to serve
	}

    location /snapshot {
        limit_req zone=rgs_snapshots burst=10 nodelay;
        limit_rate 5m;

        try_files $uri $uri/ /res/symlinks/$1.bin;
        autoindex on;
        rewrite ^/snapshot/(\d+)$ /snapshot/$1.bin break;
        rewrite ^/snapshot/(\d+)\.bin$ /snapshot/$1 break;
    }


    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot


}
server {
    if ($host = rgs.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name rgs.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot


}
