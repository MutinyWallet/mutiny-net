include /root/mutiny-net/nginx/cloudflare-only.conf;

server {
	server_name analytics.mutinynet.com;

	# The dashboard is gated by Cloudflare Access. Refuse direct origin hits so
	# Access cannot be bypassed. See cloudflare-only.conf.
	if ($cloudflare_edge = 0) {
		return 403;
	}

	location / {
		proxy_pass http://127.0.0.1:8083;
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	}

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com-0002/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com-0002/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
server {
    if ($host = analytics.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name analytics.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot
}
