server {
	server_name mutinynet.com;
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
        add_header Cache-Control "public, max-age=60" always;
        return 200 '{"pools":[{"poolId":1,"name":"Unknown","link":"https://learnmeabitcoin.com/technical/coinbase-transaction","blockCount":79431,"rank":1,"emptyBlocks":30123,"slug":"unknown","avgMatchRate":null,"avgFeeDelta":null,"poolUniqueId":0}],"blockCount":79431,"lastEstimatedHashrate":147976.0707714739,"lastEstimatedHashrate3d":147896.6113425926,"lastEstimatedHashrate1w":147961.761558658}';
    }

    location = /api/v1/mining/pools/1w {
        default_type application/json;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Expose-Headers "X-Total-Count" always;
        add_header X-Total-Count "3264596" always;
        add_header Cache-Control "public, max-age=60" always;
        return 200 '{"pools":[{"poolId":1,"name":"Unknown","link":"https://learnmeabitcoin.com/technical/coinbase-transaction","blockCount":18495,"rank":1,"emptyBlocks":9027,"slug":"unknown","avgMatchRate":null,"avgFeeDelta":null,"poolUniqueId":0}],"blockCount":18495,"lastEstimatedHashrate":147971.4505318964,"lastEstimatedHashrate3d":147896.6113425926,"lastEstimatedHashrate1w":147961.1008964977}';
    }

    location ^~ /api/v1/mining/ {
        default_type application/json;
        add_header Access-Control-Allow-Origin "*" always;
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
    ssl_certificate /etc/letsencrypt/live/mutinynet.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com/privkey.pem; # managed by Certbot
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
