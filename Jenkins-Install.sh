#!/bin/bash
# set up install of Jenkins

# install Jenkins
sudo su
wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
apt-get update -y
apt-get install -y jenkins
apt-get install -y php
apt-get update -y

# sudo echo "7227-voya" | passwd --stdin root
# sudo echo -e "7227-voya\n7227-voya" | (passwd --stdin root)
# sudo echo -e "7227-voya\n7227-voya" | passwd root