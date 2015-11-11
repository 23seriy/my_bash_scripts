#!/bin/bash -x

# Prepares the application for deployment:
# Bumps version if necessary, deletes unneed directories, packs into tar and copies to QA and Staing

# $1 Bump version type (possible values: none, build, release)

if [ $# -ge 1 ]
then
 case "$1" in 
 "build") rake ni:utils:bump_build_version
	  git push origin
	;;
 "release") rake ni:utils:bump_release_version
	    git push origin		
        ;;
 esac
fi

rm -rf tmp/
cd ..
tar czfv boost.tgz --exclude='.idea' --exclude='.git' --exclude='node_modules' boost
if [ $# -ge 2 ]
then
    mv boost.tgz /var/tmp/
else
    mv boost.tgz /var/tmp/
fi
