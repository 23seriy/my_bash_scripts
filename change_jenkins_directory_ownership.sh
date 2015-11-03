#!/bin/bash

echo "Started changing ownership at: `date`"
echo "--------------------------------------"

cd /var/jenkins_home/
pwd
chown -R 1000:1000 *

echo "Finished at: `date`"
echo "======================================="
