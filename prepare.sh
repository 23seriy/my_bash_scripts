#!/bin/bash -x

# Prepares the application for deployment:
# Bumps version if necessary, deletes unneed directories, packs into tar and copies to QA and Staing

# $1 Bump version type (possible values: none, build, release)

if [ $# -ge 1 ]
then
 case "$1" in 
 "build") bundle exec rake ni:essentials:version:bump_build
	  git push origin
	;;
 "release") bundle exec rake ni:essentials:version:bump_release
	    git push origin		
        ;;
 esac
fi

#rm -rf tmp/
#cd ..
#tar czfv boost.tgz --exclude='.idea' --exclude='.git' --exclude='node_modules' boost
#if [ $# -ge 2 ]
#then
#    scp boost.tgz "$2@boost01.tokyo.aws.naturalint.com":/var/tmp/
#else
#    scp boost.tgz boost01.tokyo.aws.naturalint.com:/var/tmp/
#fi
