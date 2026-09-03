# This host is Cloudflare-proxied. The real client IP is restored from
# CF-Connecting-IP by the realip config included at http level in
# nginx.conf (cloudflare-realip.conf), so rate-limit zones and
# X-Forwarded-For key on the actual user, not the Cloudflare edge node.

# Read endpoints: page loads, status checks, session creation.
limit_req_zone $binary_remote_addr zone=faucet_read:10m rate=30r/m;
# Payment endpoints: withdrawals, invoice creation, channel opens.
# The backend's per-IP daily budgets are the real guard; this only
# smooths bursts.
limit_req_zone $binary_remote_addr zone=faucet_write:10m rate=6r/m;

server {
	server_name faucet.mutinynet.com;

	limit_req_status 429;

	location /api/bolt11 {
		add_header 'Access-Control-Allow-Origin' '*' always;
		add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
		add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Cotent-Length' always;
		include /root/mutiny-net/nginx/hsts.conf;

		limit_req zone=faucet_write burst=3 nodelay;

		# Forward the real client IP so backend rate limits cannot be spoofed
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	location /auth/ {
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	# Withdrawal execution
	location /api/lnurlw/callback {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	# Withdrawal session creation (wallets poll this)
	location /api/lnurlw {
		limit_req zone=faucet_read burst=20 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	# Payment surfaces
	location /api/lightning {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	location /api/onchain {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	location /api/channel {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	location /api/arkade {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	location /api/reorg {
		limit_req zone=faucet_write burst=3 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;

		proxy_pass http://127.0.0.1:3001;
	}

	# Everything else under /api (limits, status, config)
	location /api/ {
		limit_req zone=faucet_read burst=20 nodelay;

		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-Proto $scheme;
		proxy_set_header X-Forwarded-Host $host;
		proxy_set_header X-Forwarded-Port $server_port;

		proxy_pass http://127.0.0.1:3001;
	}


	location / {
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
		include /root/mutiny-net/nginx/hsts.conf;
		proxy_pass http://127.0.0.1:3000;
	}


    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot


}
server {
    if ($host = faucet.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name faucet.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot

}
