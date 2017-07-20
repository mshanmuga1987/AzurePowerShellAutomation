#!/bin/bash
# set up install of MariaDB-Server

# install LAMP stack
sudo yum install -y apache mariadb-server php php-mysql  

# restart and enable Mariadb
sudo systemctl start mariadb
sudo systemctl enable mariadb
# restart and enable Apache
sudo systemctl restart httpd
sudo systemctl enable httpd