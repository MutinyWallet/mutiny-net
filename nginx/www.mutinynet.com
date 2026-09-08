# Per-IP limits, mirroring mutinynet.com. nginx.conf applies realip at http
# level, so $binary_remote_addr is the real client address behind Cloudflare.
limit_req_zone $binary_remote_addr zone=www_api:10m rate=20r/s;
limit_req_zone $binary_remote_addr zone=www_history:10m rate=2r/s;
limit_conn_zone $binary_remote_addr zone=www_ws:10m;

server {
	server_name www.mutinynet.com;

	limit_req_status 429;
	limit_conn_status 429;

	location /api/v1/ws {
		limit_conn www_ws 10;
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
	# Electrs bulk and maintenance routes. Nothing public needs them.
	location ^~ /api/internal/ {
		return 404;
	}

	# Address and scripthash history. Upstream does not cap max_txs on every
	# route, so bound the request rate and refuse four-digit page sizes.
	location ~ ^/api/(address|scripthash)/[^/]+/txs {
		limit_req zone=www_history burst=5 nodelay;
		if ($arg_max_txs ~ "^[+]?[0-9]{4,}$") {
			return 400;
		}
		include /root/mutiny-net/nginx/electrs-cors.conf;
		rewrite ^/api/(.*)$ /$1 break;
		proxy_pass http://127.0.0.1:3003;
	}

	location /api/ {
		limit_req zone=www_api burst=40 nodelay;
		if ($arg_max_txs ~ "^[+]?[0-9]{4,}$") {
			return 400;
		}
		include /root/mutiny-net/nginx/electrs-cors.conf;
		proxy_pass http://127.0.0.1:3003/;
	}

	# mainnet API
	location /ws {
		limit_conn www_ws 10;
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
