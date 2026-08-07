server {
	server_name cashu.mutinynet.com;

	location / {
		add_header 'Access-Control-Allow-Origin' '*' always;
		add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
		add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Cotent-Length' always;

		# Nutshell uses these headers for per-client rate limiting. Override both
		# so a direct client cannot supply a spoofed address.
		proxy_set_header CF-Connecting-IP $remote_addr;
		proxy_set_header X-Forwarded-For $remote_addr;
		proxy_pass http://127.0.0.1:3338;
	}

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot



}
server {
    if ($host = cashu.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name cashu.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot


}
