#!/usr/bin/env bash

count=0
proj_old=~/android
proj_new=~/android_new
mkdir -p ~/android_new/

rm -rf ~/android_new/*

cd $proj_old

git branch -r > ~/br
cd "$proj_new"
git init

IFS=$'\n'       # make newlines the only separator
for branch in $(cat ~/br)
do
    br=`echo $branch | tr -d '[:space:]' | sed -e "s/^origin\///"`
    echo $br
    cd $proj_old
    git checkout $br
    git branch
    cd "$proj_new"
    git checkout --orphan "$br"
    rm -rf ./*
    cp -r "$proj_old"/* .

    (( count++ ))
    echo $count
    git add .
    git commit -m "Import $br"

done
