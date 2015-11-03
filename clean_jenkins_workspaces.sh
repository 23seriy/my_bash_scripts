#!/bin/bash

date
find /var/jenkins_home/jobs -name workspace_ws-cleanup*
path=$(find /var/jenkins_home/jobs -name workspace_ws-cleanup*)
rm -rf $path
find /var/jenkins_home/jobs -name workspace_ws-cleanup*
