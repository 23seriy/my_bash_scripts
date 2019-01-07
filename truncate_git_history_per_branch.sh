#!/usr/bin/env bash

count=0
proj_old=~/android
proj_new=~/android_new
mkdir -p ~/android_new/

rm -rf $proj_new
mkdir $proj_new

cd $proj_old

git branch -r | grep -v "origin/HEAD" > ~/br
cd "$proj_new"
git init

for branch in $(cat ~/br)
do
    echo $branch
    br=`echo $branch | tr -d '[:space:]' | sed -e "s/^origin\///"`
    echo $br
    cd $proj_old
    git checkout $br
    git branch
    cd "$proj_new"
    git checkout --orphan "$br"
    rm -rf ./*
    echo "Start copying $br branch"
    cp -r "$proj_old"/* .
    cp "$proj_old"/.gitignore .

    (( count++ ))
    echo $count
    git add .
    git commit -m "Import $br branch"

done
