map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
	server_name mutinynet.com;

    location /electrum-websocket {
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
        proxy_pass http://127.0.0.1:8999;
    }


    location /api/ {
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
