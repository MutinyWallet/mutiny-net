server {
	server_name fortune.mutinynet.com;

	location / {
		add_header 'Access-Control-Allow-Origin' '*' always;
		add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
		add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Content-Length,Authorization' always;

		proxy_pass http://127.0.0.1:3402;
	}

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/mutinynet.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/mutinynet.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot



}
server {
    if ($host = fortune.mutinynet.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


	server_name fortune.mutinynet.com;
    listen 80;
    return 404; # managed by Certbot


}
