#!/bin/bash

# This script sets up a private Docker repository on an Ubuntu 20.04 EC2 instance.
# Run this script with sudo permissions.

RED='\033[0;31m'
NC='\033[0m'
YELLOW='\033[33m'
GREEN='\033[32m'

if [ "$(id -u)" -ne 0; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

echo "Enter the Domain Name:"
read -r domain_name

echo -e "${YELLOW}...Updating packages${NC}"
apt-get update && apt-get upgrade -y

# Install Docker if not installed
if ! [ -x "$(command -v docker)" ]; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
fi

echo -e "${YELLOW}...Installing Docker Compose${NC}"
apt-get install -y docker-compose

# Install Certbot and Nginx plugin
echo -e "${YELLOW}...Installing Certbot and Nginx plugin${NC}"
apt-get install -y certbot python3-certbot-nginx

echo -e "${YELLOW}...Obtaining SSL certificate${NC}"
certbot certonly --nginx --email saranyasreedharan23@gmail.com --agree-tos --eff-email -d "$domain_name"

# Create directories for registry
mkdir -p /registry/{auth,data,nginx}

# Create authentication file
apt-get install -y apache2-utils
htpasswd -Bc /registry/auth/htpasswd admin

# Create Docker Compose file
cat <<EOL > /registry/docker-compose.yml
version: '3'

services:
  registry:
    image: registry:2
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
    volumes:
      - /registry/data:/var/lib/registry
      - /registry/auth:/auth

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /registry/auth:/etc/nginx/auth
EOL

# Create Nginx configuration file
cat <<EOL > /registry/nginx.conf
events { }

http {
    upstream docker-registry {
        server registry:5000;
    }

    server {
        listen 443 ssl;
        server_name $domain_name;

        ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;

        client_max_body_size 4G;  

        location /v2/ {
            proxy_pass http://docker-registry;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            auth_basic "Docker Registry";
            auth_basic_user_file /etc/nginx/auth/htpasswd;
        }
    }
}
EOL

# Start Docker Compose
cd /registry || exit
docker-compose up -d

echo -e "${GREEN}Docker private registry setup completed successfully.${NC}"

# Instructions for client machines
echo -e "${YELLOW}To login to the private registry from any machine, use the following command:${NC}"
echo -e "${YELLOW} sudo docker login $domain_name${NC}"

# Push and Pull Test Instructions
echo -e "${YELLOW}To test the registry, follow these steps:${NC}"
echo -e "1. Pull a small image: sudo docker pull busybox"
echo -e "2. Tag the image: sudo docker tag busybox $domain_name/busybox:test"
echo -e "3. Push the image: sudo docker push $domain_name/busybox:test"
echo -e "4. On another machine, pull the image: sudo docker pull $domain_name/busybox:test"
