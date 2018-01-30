#!/bin/bash
# set up install of Jenkins

# install Jenkins
wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt-get update
sudo apt-get install jenkins
sudo apt-get install php
sudo apt-get update

# sudo echo "7227-voya" | passwd --stdin root
sudo echo -e "7227-voya\n7227-voya" | (passwd --stdin root)
# sudo echo -e "7227-voya\n7227-voya" | passwd root