#!/bin/bash

#This script is used to create private docker repository in ubuntu 20.04 ec2 instance
#Run this sctript with sudo permissions ( sudo su)

RED='\033[0;31m'  # Red colored text
NC='\033[0m'      # Normal text
YELLOW='\033[33m'  # Yellow Color
GREEN='\033[32m'   # Green Color

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

echo "Enter the Domain_name:"
read -r domain_name


echo -e "${YELLOW}... updating packages${NC}"
# Update package information
if ! sudo apt update; then
    echo -e "${RED}The system update failed.${NC}"
    exit 1
fi

# Check if Docker is installed
if [ -x "$(command -v docker)" ]; then
    echo "${GREEN}Docker is already installed.${NC}"
else
    # Install Docker
    echo -e "${YELLOW}Installing Docker...${NC}"
    sudo apt-get update
    sudo apt-get install -y docker.io
    if ! [ -x "$(command -v docker)" ]; then
        echo -e "${RED}Docker installation failed.${NC}"
        exit 1
    else
        echo "${GREEN}Docker is successfully installed.${NC}"
    fi
fi

echo -e "${YELLOW}...checking the docker is running successfully or not...${NC}"

# Check if Docker is running
if sudo systemctl is-active --quiet docker; then
    echo "${GREEN}Docker is running.${NC}"
else
    # Start Docker
    echo "${YELLOW}Starting Docker...${NC}"
    sudo systemctl start docker
    sudo systemctl enable docker
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Docker Successfully started.${NC}"
    else
        echo -e "${RED}Docker Failed to start.${NC}"
        exit 1
    fi
fi


echo -e "${YELLOW}...configuring the docker daemon.json...${NC}"
# Configure Docker daemon
if ! sudo bash -c "cat <<EOL > /etc/docker/daemon.json
{
  \"insecure-registries\": [\"$domain_name\"]
}
EOL"; then
    echo -e "${RED}The Docker daemon configuration failed.${NC}"
    exit 1
fi

echo -e "${YELLOW}...restarting the docker...${NC}"
# Restart Docker
if ! sudo systemctl restart docker; then
    echo -e "${RED}Failed to restart Docker after modifying the daemon.json.${NC}"
    exit 1
fi


echo -e "${YELLOW}...Installing Certbot and its Nginx plugin${NC}"
if ! sudo apt install -y certbot python3-certbot-nginx; then 
    echo -e "${RED}Package installation failed.${NC}"
    echo -e "${RED}Please check the error message above for more details.${NC}"
    exit 1
fi

sudo certbot certonly --nginx



echo -e "${YELLOW}...updating the system...${NC}"
if ! sudo apt update; then
  echo -e "${RED}System update failed.${NC}"
  exit 1
fi


echo -e "${YELLOW}...installing the docker-compose...${NC}"
if ! sudo apt install -y docker-compose; then 
  echo -e "${RED}Failed to install Docker Compose.${NC}"
  exit 1
else
  echo -e "${GREEN}Docker Compose successfully installed.${NC}"
fi

echo -e "${YELLOW}Creating directories...${NC}"

# Create the 'registry' directory
mkdir -p registry
if [ $? -eq 0 ]; then
    echo -e "${GREEN}'registry' directory created.${NC}"
else
    echo -e "${RED}Failed to create 'registry' directory.${NC}"
    exit 1
fi

# Move into the 'registry' directory
cd registry
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to navigate to 'registry' directory.${NC}"
    exit 1
fi

# Create the 'auth' directory
mkdir auth
if [ $? -eq 0 ]; then
    echo -e "${GREEN}'auth' directory created.${NC}"
else
    echo -e "${RED}Failed to create 'auth' directory.${NC}"
    exit 1
fi

# Create the 'nginx' directory
mkdir nginx
if [ $? -eq 0 ]; then
    echo -e "${GREEN}'nginx' directory created.${NC}"
else
    echo -e "${RED}Failed to create 'nginx' directory.${NC}"
    exit 1
fi

# Move into the 'nginx' directory
cd nginx
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to navigate to 'nginx' directory.${NC}"
    exit 1
fi

# Create the 'conf.d' directory
mkdir conf.d
if [ $? -eq 0 ]; then
    echo -e "${GREEN}'conf.d' directory created.${NC}"
else
    echo -e "${RED}Failed to create 'conf.d' directory.${NC}"
    exit 1
fi

# Create the 'ssl' directory
mkdir ssl
if [ $? -eq 0 ]; then
    echo -e "${GREEN}'ssl' directory created.${NC}"
else
    echo -e "${RED}Failed to create 'ssl' directory.${NC}"
    exit 1
fi

cd .. || exit 1

echo -e "${YELLOW}Creating docker-compose.yml...${NC}"

# Create docker-compose.yml using nano
cat <<EOL > docker-compose.yml
version: '3'
services:
#Registry
  registry:
    image: registry:2
    restart: always
    ports:
    - "5000:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry-Realm
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/registry.passwd
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
    volumes:
      - registrydata:/data
      - ./auth:/auth
    networks:
      - mynet
#Nginx Service
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    tty: true
    ports:
      - "8080:80"
      - "8443:443"
    volumes:
      - ./nginx/conf.d/:/etc/nginx/conf.d/
      - ./nginx/ssl/:/etc/nginx/ssl/
    networks:
      - mynet
#Docker Networks
networks:
  mynet:
    driver: bridge
#Volumes
volumes:
  registrydata:
    driver: local
EOL

if [ $? -eq 0 ]; then
    echo -e "${GREEN}docker-compose.yml created successfully.${NC}"
else
    echo -e "${RED}Failed to create docker-compose.yml.${NC}"
    exit 1
fi

cd nginx/conf.d/


echo -e "${YELLOW}Creating registry.conf...${NC}"

# Create registry.conf using nano
cat <<EOL > /etc/nginx/sites-available/$domain_name.conf

server {
    listen 443 ssl;
    server_name www.$domain_name $domain_name;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem; 
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem; 

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL


if [ $? -eq 0 ]; then
    echo -e "${GREEN}$domain_name.conf created successfully.${NC}"
else
    echo -e "${RED}Failed to create $domain_name.conf.${NC}"
    exit 1
fi

sudo ln -s /etc/nginx/sites-available/$domain_name.conf /etc/nginx/sites-enabled/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}$domain_name.conf SOFTLINK successfully.${NC}"
else
    echo -e "${RED}Failed to create SOFTLINK $domain_name.conf.${NC}"
    exit 1
fi

if sudo nginx -t; then
    echo -e "${GREEN}nginx configuration is correct${NC}"
else
    echo -e "${YELLOW}nginx configuratin error${NC}"
    exit 1
fi


if sudo systemctl restart nginx; then
    echo -e "${GREEN}nginx restarted successfully${NC}"
else
    echo -e "${YELLOW}nginx restart failed${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating additional volume ...${NC}"

# Create additional.conf using nano
cat <<EOL > additional.conf
client_max_body_size 2G;
EOL

if [ $? -eq 0 ]; then
    echo -e "${GREEN}additional.conf created successfully.${NC}"
else
    echo -e "${RED}Failed to create additional.conf.${NC}"
    exit 1
fi

cd .. || exit 1

echo -e "${YELLOW}...the ssl files are copying...${NC}"

# Copy SSL files
sudo cp /etc/letsencrypt/live/$domain_name/fullchain.pem ssl/ || {
    echo -e "${RED}Failed to copy fullchain.pem.${NC}"
    exit 1
}

sudo cp /etc/letsencrypt/live/$domain_name/privkey.pem ssl/ || {
    echo -e "${RED}Failed to copy privkey.pem.${NC}"
    exit 1
}

#cd registry/auth
cd .. || exit 1
cd auth



echo -e "${YELLOW}...installing apache2-utils...${NC}"
sudo apt install -y apache2-utils || {
    echo -e "${RED}Failed to install apache2-utils.${NC}"
    exit 1
}

echo -e "${YELLOW}...creating registry.passwd file...${NC}"
htpasswd -Bc registry.passwd admin || {
    echo -e "${RED}Failed to create registry.passwd file.${NC}"
    exit 1
}

cd .. || exit 1

# Create rootCA.crt
sudo openssl x509 -in /etc/letsencrypt/live/$domain_name/fullchain.pem -inform PEM -out rootCA.crt
if [ $? -eq 0 ]; then
    echo -e "${GREEN}rootCA.crt created successfully.${NC}"
else
    echo -e "${RED}Failed to create rootCA.crt.${NC}"
    exit 1
fi

echo -e "${YELLOW}Copying rootCA.crt to Docker certificates directory...${NC}"

# Copy rootCA.crt to Docker certificates directory
sudo mkdir -p /etc/docker/certs.d/$domain_name/
sudo cp rootCA.crt /etc/docker/certs.d/$domain_name/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}rootCA.crt copied to Docker certificates directory.${NC}"
else
    echo -e "${RED}Failed to copy rootCA.crt to Docker certificates directory.${NC}"
    exit 1
fi

echo -e "${YELLOW}Copying rootCA.crt to extra CA certificates directory...${NC}"

# Copy rootCA.crt to extra CA certificates directory
sudo mkdir -p /usr/share/ca-certificates/extra/
sudo cp rootCA.crt /usr/share/ca-certificates/extra/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}rootCA.crt copied to extra CA certificates directory.${NC}"
else
    echo -e "${RED}Failed to copy rootCA.crt to extra CA certificates directory.${NC}"
    exit 1
fi

echo -e "${YELLOW}Reconfiguring CA certificates...${NC}"

# Reconfigure CA certificates
sudo dpkg-reconfigure ca-certificates
if [ $? -eq 0 ]; then
    echo -e "${GREEN}CA certificates reconfigured successfully.${NC}"
else
    echo -e "${RED}Failed to reconfigure CA certificates.${NC}"
    exit 1
fi

echo -e "${YELLOW}Restarting Docker service...${NC}"

# Restart Docker service
sudo systemctl restart docker
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Docker service restarted successfully.${NC}"
else
    echo -e "${RED}Failed to restart Docker service.${NC}"
    exit 1
fi


echo -e "${YELLOW}Starting Docker Compose...${NC}"

# Start Docker Compose

sudo usermod -aG docker $USER

echo -e "${YELLOW}...the docker compose starting...${NC}"

sudo docker-compose up -d
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Docker Compose started successfully.${NC}"
else
    echo -e "${RED}Failed to start Docker Compose.${NC}"
    exit 1
fi


echo -e "${YELLOW}Checking Docker Compose status...${NC}"

# Check Docker Compose status
sudo docker-compose ps
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Docker Compose is running.${NC}"
else
    echo -e "${RED}Docker Compose is not running.${NC}"
    exit 1
fi

echo -e "${YELLOW}Pulling PHP image...${NC}"

# Pull PHP image
sudo docker pull php
if [ $? -eq 0 ]; then
    echo -e "${GREEN}PHP image pulled successfully.${NC}"
else
    echo -e "${RED}Failed to pull PHP image.${NC}"
    exit 1
fi

echo -e "${YELLOW}Tagging the PHP image...${NC}"

# Tag the PHP image
sudo docker images
sudo docker tag php:latest $domain_name/php:v2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}PHP image tagged successfully.${NC}"
else
    echo -e "${RED}Failed to tag PHP image.${NC}"
    exit 1
fi

echo -e "${YELLOW}Logging in to the private registry...${NC}"

# Log in to the private registry
sudo docker login https://$domain_name
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Logged in to the private registry.${NC}"
else
    echo -e "${RED}Failed to log in to the private registry.${NC}"
    exit 1
fi

echo -e "${YELLOW}Pushing the tagged PHP image to the private registry...${NC}"

#tag the image with private repo
sudo docker tag php:latest $domain_name/php:v2

# Push the tagged PHP image to the private registry
sudo docker push $domain_name/php:v2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}PHP image pushed to the private registry successfully.${NC}"
else
    echo -e "${RED}Failed to push PHP image to the private registry.${NC}"
    exit 1
fi