#!/bin/bash
# create dir

# create dir
sudo su
mkdir -p /home/slocal/icareapp
apt-get install -y php libapache2-mod-php php-mcrypt php-mysql php-gd php-curl
apt-get update -y
apt-get install -y apache2
apt-get install -y mysql-server
apt-get install -y redis-server

# sudo echo "7227-voya" | passwd --stdin root
# sudo echo -e "7227-voya\n7227-voya" | (passwd --stdin root)
# sudo echo -e "7227-voya\n7227-voya" | passwd root