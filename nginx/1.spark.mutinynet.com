server {
    listen 80;
    server_name 1.spark.mutinynet.com;
    
    # gRPC endpoint (main Spark operator API)
    location / {
        grpc_pass grpc://127.0.0.1:10011;
        grpc_set_header Host $host;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto $scheme;
        
        # gRPC specific settings
        grpc_read_timeout 300;
        grpc_send_timeout 300;
        client_body_timeout 300;
        client_max_body_size 10M;
        
        # Enable gRPC error details
        grpc_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
}