#!/bin/bash

# variables
DRUPAL_VERSION='8.3.0'
DRUSH_TIMEOUT=60
TIMEZONE='Europe/Moscow'
COUNTRY_CODE='RU'
PROFILE='standard'  # minimal | standard
PHP='7.0'  # 5.5 (default) | 5.6 | 7.0
SUPERUSER='admin'
PASSWORD='admin'
EMAIL='admin@admin.com'

MODULES_ENABLE='devel admin_toolbar search_kint coffee simple_sitemap metatag pathauto ctools redirect toolbar_visibility allowed_formats block_class field_formatter_class field_group permissions_filter twig_tweak twig_field_value'
MODULES_ENABLE_EXTRA='devel_generate admin_toolbar_tools metatag_open_graph'
MODULES_DISABLE='rdf tour color'


echo 'Enter short project name (one word, one dot allowed):'
read PROJECT

echo ''

echo 'Enter site name:'
read SITENAME

if [ -d $PROJECT ]; then
  echo ''
  echo 'ERROR: Project exists'
  exit 0
fi


# download drupal
if [ ! -f ~/.cache/drupal-$DRUPAL_VERSION.tar.gz ]; then
  wget https://ftp.drupal.org/files/projects/drupal-$DRUPAL_VERSION.tar.gz -O ~/.cache/drupal-$DRUPAL_VERSION.tar.gz
fi

tar -xzvf ~/.cache/drupal-$DRUPAL_VERSION.tar.gz
mv drupal-$DRUPAL_VERSION $PROJECT
cd $PROJECT


# gitignore
mv example.gitignore .gitignore
sed -i 's/# core/\/core/g' .gitignore
sed -i 's/# vendor/\/vendor/g' .gitignore

cat >> .gitignore <<EOF

# Ignore temporary files
tmp/*
node_modules
.cache
.directory

# Ingore project files
.idea
nbproject

# Files not used on production
docker-compose.yml
example.gitignore
host.yml
LICENSE.txt
modules/README.txt
profiles
README.txt
sites/default/default.services.yml
sites/default/default.settings.php
sites/default/settings.php
sites/default/settings.local.php
sites/development.services.yml
sites/example.settings.local.php
sites/example.sites.php
sites/README.txt
themes/README.txt
web.config
EOF


# copying settings files
cp sites/default/default.settings.php sites/default/settings.php
cp sites/example.settings.local.php sites/default/settings.local.php


# git init
git init
git add .
git commit -m 'Initial commit'


# patching local settings
sed -i "s/# \$settings\['cache'\]/\$settings\['cache'\]/g" sites/default/settings.local.php

cat << 'EOF' > sites/development.services.yml
# Local development services.
#
# To activate this feature, follow the instructions at the top of the
# 'example.settings.local.php' file, which sits next to this file.
parameters:
  http.response.debug_cacheability_headers: true
  twig.config:
    debug: true
    auto_reload: true
    cache: false
services:
  cache.backend.null:
    class: Drupal\Core\Cache\NullBackendFactory

EOF


# drush configuration
mkdir drush
cat << 'EOF' > drush/drushrc.php
<?php


# Download all modules into modules/contrib folder
$command_specific['dl'] = array('destination' => 'modules/contrib');
EOF


# preparing docker
echo ${PROJECT%.*} | drupal-compose

cat << EOF >> host.yml

    - PHP_INI_XDEBUG=On
    - PHP_INI_XDEBUG_REMOTE_CONNECT_BACK=On
    - PHP_INI_XDEBUG_IDEKEY=PHPSTORM
EOF

if [ "$PHP" == "5.6" ]; then
  drupal-compose service php set version 5.6
elif [ "$PHP" == "7.0" ]; then
  drupal-compose service php set version 7.0
fi

# starting server
docker-compose up -d


# timeout fixes `drush not found` error
sleep $DRUSH_TIMEOUT

mkdir tmp
# remove dot in db name and domain
drush si $PROFILE -y --db-url="mysql://container:container@localhost/${PROJECT%.*}" --site-name="${SITENAME}" --uri="${PROJECT%.*}.dev" --account-name="$SUPERUSER" --account-pass="$PASSWORD" --account-mail=$EMAIL


# drupal settings
drush cset -y system.date timezone.default $TIMEZONE
drush cset -y system.date first_day 1
drush cset -y system.date country.default $COUNTRY_CODE


# patching settings.php
chmod 755 sites/default
chmod 644 sites/default/settings.php


# configuration
mkdir sites/default/sync
sed -i "/files\/config_/d" sites/default/settings.php

cat << EOF >> sites/default/settings.php

/**
 * Config directories
 */
\$config_directories[CONFIG_SYNC_DIRECTORY] = 'sites/default/sync';

/**
 * Local dev settings.
 */
if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {
  include \$app_root . '/' . \$site_path . '/settings.local.php';
}
EOF


# commit after installing
git add .
git commit -m 'Install Drupal'


# install dev modules
drush dl -y $MODULES_ENABLE
drush en -y $MODULES_ENABLE $MODULES_ENABLE_EXTRA

# uninstall core modules
drush pm-uninstall -y $MODULES_DISABLE


# commit modules
git add .
git commit -m 'Install modules'


# dump clean db
mkdir sites/default/files/backups
drush sql-dump > sites/default/files/backups/initial-db.sql


# commit initial configuration
drush cex
git add .
git commit -m 'Initial configuration export'


# final message
cat << EOF

Go to the project directory:
cd $PROJECT

Open the project in browser:
http://${PROJECT%.*}.dev/

EOF
