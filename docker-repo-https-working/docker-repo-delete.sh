# This script is used to delete the docker repository 
# In the script I am not commented the ssl certification part. Note: more than 5 time we can't create ssl certificates for same domain


#!/bin/bash

RED='\033[0;31m'  # Red colored text
NC='\033[0m'      # Normal text
YELLOW='\033[33m'  # Yellow Color
GREEN='\033[32m'   # Green Color

echo "Enter the Domain_name:"
read -r domain_name

sudo unlink /etc/nginx/sites-enabled/$domain_name.conf


echo -e "${YELLOW}Stopping Docker Compose...${NC}"
# Stop Docker Compose
sudo docker-compose down

echo -e "${YELLOW}Removing Docker Compose...${NC}"
# Remove Docker Compose
sudo apt remove --purge -y docker-compose

echo -e "${YELLOW}Reverting Docker daemon.json...${NC}"
# Revert Docker daemon.json
sudo rm /etc/docker/daemon.json

echo -e "${YELLOW}Removing Docker...${NC}"
# Remove Docker and its configurations
sudo apt remove --purge -y docker.io
sudo rm -rf /etc/docker /usr/share/ca-certificates/extra/rootCA.crt /usr/local/bin/docker-compose

echo -e "${YELLOW}Removing Nginx...${NC}"
# Remove Nginx and its configurations
sudo systemctl stop nginx
sudo apt remove --purge -y nginx

echo -e "${YELLOW}Removing SSL certificates and CA certificates...${NC}"
# Remove SSL certificates and CA certificates
#sudo rm -rf /etc/letsencrypt/live/$domain_name /etc/docker/certs.d/$domain_name /usr/share/ca-certificates/extra/rootCA.crt

echo -e "${YELLOW}Reverting /etc/hosts file...${NC}"
# Revert /etc/hosts file
sudo sed -i "/$domain_name/d" /etc/hosts

echo -e "${YELLOW}Removing directories created by the script...${NC}"
# Remove directories created by the script
sudo rm -rf registry


echo -e "${GREEN}Revert script executed successfully.${NC}"