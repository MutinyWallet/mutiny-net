# Cloudflare-proxied: log and forward the real client IP.
include /root/mutiny-net/nginx/cloudflare-realip.conf;

server {
	server_name www.mutinynet.com;
	location /api/v1/ws {
		proxy_pass http://127.0.0.1:8999/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "Upgrade";
	}
	# Mining statistics scan millions of signet blocks. Serve frozen snapshots
	# for the two endpoints used by the frontend instead of querying MariaDB.
	location = /api/v1/mining/pools/1m {
		default_type application/json;
		add_header Access-Control-Allow-Origin "*" always;
		add_header Access-Control-Expose-Headers "X-Total-Count" always;
		add_header X-Total-Count "3264595" always;
		include /root/mutiny-net/nginx/hsts.conf;
		add_header Cache-Control "public, max-age=60" always;
		alias /var/www/mutinynet-static/mining/pools/1m.json;
	}
	location = /api/v1/mining/pools/1w {
		default_type application/json;
		add_header Access-Control-Allow-Origin "*" always;
		add_header Access-Control-Expose-Headers "X-Total-Count" always;
		add_header X-Total-Count "3264596" always;
		include /root/mutiny-net/nginx/hsts.conf;
		add_header Cache-Control "public, max-age=60" always;
		alias /var/www/mutinynet-static/mining/pools/1w.json;
	}
	location ^~ /api/v1/mining/ {
		default_type application/json;
		add_header Access-Control-Allow-Origin "*" always;
		include /root/mutiny-net/nginx/hsts.conf;
		return 404 '{"error":"Mining API disabled"}';
	}
	location /api/v1 {
		rewrite ^/api/v1(.*)$ /api$1 last;
	}
	location /api/ {
		if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
        if ($request_method = 'GET') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
        }
        if ($request_method = 'POST') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
        }
		include /root/mutiny-net/nginx/hsts.conf;
		proxy_pass http://127.0.0.1:3003/;
	}

	# mainnet API
	location /ws {
		proxy_pass http://127.0.0.1:8999/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "Upgrade";
	}
	location / {
		proxy_pass http://127.0.0.1:8080;
	}


    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = www.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name www.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot
}
