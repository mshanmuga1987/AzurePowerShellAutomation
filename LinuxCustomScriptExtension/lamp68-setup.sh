#!/bin/bash
# set up LAMP Stack on CentOS6.8

# install LAMP stack
sudo yum install -y apache mysql-server php php-mysql

# start and enable Apache
sudo service httpd start
sudo chkconfig httpd on
# start and enable Mysql-Server
sudo service mysqld start
sudo chkconfig mysqld on

#reset root password
sudo echo -e "7227-voya\n7227-voya" | (passwd --stdin root)


