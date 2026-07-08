#!/bin/bash
sudo dnf install ansible-core -y
ansible-pull -i localhost, -U https://github.com/manjunath-bee/docker_new.git -d /tmp/ansible-repo anisible-tf/main.yaml -e COMPONENT=backend -e ENVIRONMENT=$1
