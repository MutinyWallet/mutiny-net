server {
	server_name analytics.mutinynet.com;

	# Only allow Cloudflare IPs
	allow 173.245.48.0/20;
	allow 103.21.244.0/22;
	allow 103.22.200.0/22;
	allow 103.31.4.0/22;
	allow 141.101.64.0/18;
	allow 108.162.192.0/18;
	allow 190.93.240.0/20;
	allow 188.114.96.0/20;
	allow 197.234.240.0/22;
	allow 198.41.128.0/17;
	allow 162.158.0.0/15;
	allow 104.16.0.0/13;
	allow 104.24.0.0/14;
	allow 172.64.0.0/13;
	allow 131.0.72.0/22;
	deny all;

	location / {
		proxy_pass http://127.0.0.1:8083;
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	}

	listen 80;
}
