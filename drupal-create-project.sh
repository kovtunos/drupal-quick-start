#!/bin/bash

VERSION="8.0.5"


echo "Enter short project name: "
read PROJECT

if [ -d $PROJECT ]; then
  echo ''
  echo "ERROR: Project exists"
  exit 0
fi


# download drupal
if [ ! -f ~/.cache/drupal-$VERSION.tar.gz ]; then
  wget https://ftp.drupal.org/files/projects/drupal-$VERSION.tar.gz -O ~/.cache/drupal-$VERSION.tar.gz
fi

tar -xzvf ~/.cache/drupal-$VERSION.tar.gz
mv drupal-$VERSION $PROJECT
cd $PROJECT


# gitignore
mv example.gitignore .gitignore
sed -i 's/# core/core/g' .gitignore
sed -i 's/# vendor/vendor/g' .gitignore
sed -i 's/sites\/\*\/settings\*.php/# sites\/\*\/settings\*.php/g' .gitignore
sed -i 's/sites\/\*\/services\*.yml/# sites\/\*\/services\*.yml/g' .gitignore

cat >> .gitignore <<EOF

# Ignore temporary files
temp/*
node_modules
nbproject
.idea
EOF


# copying settings files
cp sites/default/default.settings.php sites/default/settings.php
cp sites/example.settings.local.php sites/default/settings.local.php


# git init
git init
git add .
git commit -m 'Initial commit.'


# patching local settings
sed -i "s/# \$settings\['cache'\]/\$settings\['cache'\]/g" sites/default/settings.local.php

cat << 'EOF' >> sites/development.services.yml

parameters:
  twig.config:
    debug: true
    auto-reload: true
    cache: false
EOF


# drush configuration
mkdir drush
cat << 'EOF' > drush/drushrc.php
<?php


# Download all modules into modules/contrib folder
$command_specific['dl'] = array('destination' => 'modules/contrib');
EOF


# commit after patching
git add .
git commit -m 'Patch settings for dev environment.'


# preparing docker
echo $PROJECT | drupal-compose
drupal-compose service php set version 5.6

cat << EOF >> host.yml

    - PHP_INI_XDEBUG=On
    - PHP_INI_XDEBUG_REMOTE_CONNECT_BACK=On
    - PHP_INI_XDEBUG_IDEKEY=netbeans-xdebug
EOF


# commit after setting docker
git add .
git commit -m 'Dockerize drupal settings.'


# starting server
docker-compose up -d


# timeout fixes drush `not found` error
sleep 60

drush si standard -y --db-url="mysql://container:container@localhost/$PROJECT" --site-name=$PROJECT --uri="$PROJECT.dev" --account-name=admin --account-pass=admin --account-mail=admin@admin.com


# patching settings.php
chmod 755 sites/default
chmod 644 sites/default/settings.php

cat << EOF >> sites/default/settings.php

/**
 * Local dev settings.
 */
if (file_exists(__DIR__ . '/settings.local.php')) {
  include __DIR__ . '/settings.local.php';
}
EOF

# commit after installing
git add .
git commit -m 'Install Drupal.'


# install dev modules
drush dl -y admin_toolbar devel
drush en -y admin_toolbar devel devel_generate kint

drush status


# commit dev modules
git add .
git commit -m 'Install dev modules.'


# dump clean db
mkdir sites/default/files/backup
drush sql-dump > sites/default/files/backup/initial-db.sql


# final message
cat << EOF

Open the project in browser:
http://$PROJECT.dev/

EOF
