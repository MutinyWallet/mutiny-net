map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

# Per-IP limits. nginx.conf applies realip at http level, so $binary_remote_addr
# is the real client address behind Cloudflare.
limit_req_zone $binary_remote_addr zone=mn_api:10m rate=20r/s;
limit_req_zone $binary_remote_addr zone=mn_history:10m rate=2r/s;
limit_conn_zone $binary_remote_addr zone=mn_ws:10m;

server {
	server_name mutinynet.com;

    limit_req_status 429;
    limit_conn_status 429;

    location /electrum-websocket {
        limit_conn mn_ws 10;
        proxy_pass http://127.0.0.1:50050; # Point to the websocat bridge
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;

        # Electrum connections are long-lived; prevent Nginx from timing out
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

	location /api/v1/ws {
		limit_conn mn_ws 10;
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

    location /api/v1/ {
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Max-Age' 1728000 always;
            add_header 'Content-Type' 'text/plain; charset=utf-8' always;
            add_header 'Content-Length' 0 always;
            return 204;
        }

        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

        include /root/mutiny-net/nginx/hsts.conf;
        limit_req zone=mn_api burst=40 nodelay;
        proxy_pass http://127.0.0.1:8999;
    }


    # Electrs bulk and maintenance routes. Nothing public needs them; the
    # mempool backend reaches electrs on the Compose network.
    location ^~ /api/internal/ {
        return 404;
    }

    # Address and scripthash history. Upstream does not cap max_txs on every
    # route, so bound the request rate instead.
    location ~ ^/api/(address|scripthash)/[^/]+/txs {
        limit_req zone=mn_history burst=5 nodelay;
        # Electrs does not cap max_txs on every history route. Refuse
        # four-digit and larger values; the defaults are 25 and 50.
        if ($arg_max_txs ~ "^[+]?[0-9]{4,}$") {
            return 400;
        }
        include /root/mutiny-net/nginx/electrs-cors.conf;
        rewrite ^/api/(.*)$ /$1 break;
        proxy_pass http://127.0.0.1:3003;
    }

    location /api/ {
        limit_req zone=mn_api burst=40 nodelay;
        # Electrs does not cap max_txs on every history route. Refuse
        # four-digit and larger values; the defaults are 25 and 50.
        if ($arg_max_txs ~ "^[+]?[0-9]{4,}$") {
            return 400;
        }
        include /root/mutiny-net/nginx/electrs-cors.conf;
        proxy_pass http://127.0.0.1:3003/;
    }

	# mainnet API
	location /ws {
		limit_conn mn_ws 10;
		proxy_pass http://127.0.0.1:8999/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "Upgrade";
	}
	location / {
		proxy_pass http://127.0.0.1:8080;

		proxy_set_header Accept-Encoding "";
		sub_filter '</body>' '<div id="faucet-link" style="display:none;position:fixed;bottom:10px;right:10px;z-index:9999;"><a href="https://faucet.mutinynet.com" target="_blank" style="background:#1a9436;color:white;padding:8px 16px;border-radius:4px;text-decoration:none;font-family:sans-serif;">Faucet</a></div><script>if(location.pathname==="/")document.getElementById("faucet-link").style.display="block";</script></body>';
		sub_filter_once on;
	}


    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name mutinynet.com;
    listen 80;
    return 404; # managed by Certbot
}
