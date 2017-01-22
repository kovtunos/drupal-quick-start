#!/bin/bash

# variables
DRUPAL_VERSION="7.53"
DRUSH_TIMEOUT=60
TIMEZONE='Europe/Moscow'
COUNTRY_CODE='RU'

SUPERUSER='admin'
PASSWORD='admin'
EMAIL='admin@admin.com'

echo "Enter short project name: "
read PROJECT

if [ -d $PROJECT ]; then
  echo ''
  echo "ERROR: Project exists"
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
cat >> .gitignore <<EOF

# Ignore temporary files
tmp/*
node_modules
.cache
.directory

# Ingore project files
.idea
.netbeans
nbproject
*ftpconfig*

# Files not used on production
CHANGELOG.txt
COPYRIGHT.txt
INSTALL.mysql.txt
INSTALL.pgsql.txt
INSTALL.sqlite.txt
INSTALL.txt
LICENSE.txt
MAINTAINERS.txt
README.txt
UPGRADE.txt
sites/README.txt
themes/README.txt
sites/example.sites.php
sites/default/default.settings.php
sites/default/settings.local.php
docker-compose.yml
host.yml
web.config
EOF


# copying settings files
cp sites/default/default.settings.php sites/default/settings.php


# git init
git init
git add .
git commit -m 'Initial commit'


# local debug settings
cat << 'EOF' > sites/default/settings.local.php
<?php

/**
 * Theme debugging.
 */
$conf['theme_debug'] = TRUE;

/**
 * CSS/JS aggregated file gzip compression:
 */
$conf['css_gzip_compression'] = FALSE;
$conf['js_gzip_compression'] = FALSE;
EOF


# drush configuration
mkdir sites/all/drush
cat << 'EOF' > sites/all/drush/drushrc.php
<?php

# Download all modules into contrib folder
$command_specific['dl'] = array('destination' => 'sites/all/modules/contrib');
EOF


# preparing docker
echo $PROJECT | drupal-compose

cat << EOF >> host.yml

    - PHP_INI_XDEBUG=On
    - PHP_INI_XDEBUG_REMOTE_CONNECT_BACK=On
    - PHP_INI_XDEBUG_IDEKEY=netbeans-xdebug
EOF


# starting server
docker-compose up -d

# timeout fixes `drush not found` error
sleep $DRUSH_TIMEOUT

mkdir tmp
drush si standard -y --db-url="mysql://container:container@localhost/$PROJECT" --site-name=$PROJECT --uri="$PROJECT.dev" --account-name=$SUPERUSER --account-pass=$PASSWORD --account-mail=$EMAIL


# drupal settings
drush vset date_default_timezone $TIMEZONE -y
drush vset site_default_country $COUNTRY_CODE -y
drush vset configurable_timezones 0 -y
drush vset user_default_timezone 0 -y
drush vset date_first_day 1 -y
drush vset cache 0
drush vset preprocess_css 0
drush vset preprocess_js 0


# patching settings.php
chmod 755 sites/default
chmod 644 sites/default/settings.php


# enable local settings
cat << 'EOF' >> sites/default/settings.php

/**
 * Local dev settings.
 */
if (file_exists(__DIR__ . '/settings.local.php')) {
  include __DIR__ . '/settings.local.php';
}
EOF


# commit after installing
git add .
git commit -m 'Install Drupal'

# disable core modules
drush dis -y rdf overlay color dashboard toolbar search

# uninstall core modules
drush pm-uninstall -y rdf overlay color dashboard toolbar search

# download contrib modules
drush dl -y admin_menu admin_views module_filter devel backup_migrate browsersync coffee fences globalredirect \
  libraries metatag transliteration pathauto token views views404 xmlsitemap

# install contrib modules
drush en -y admin_menu admin_menu_toolbar admin_views module_filter devel devel_generate  backup_migrate browsersync coffee fences globalredirect \
  libraries metatag metatag_opengraph transliteration pathauto token views views_ui views404 xmlsitemap xmlsitemap_node xmlsitemap_menu


# commit modules
git add .
git commit -m 'Install core modules'


# dump clean db
mkdir sites/default/files/backups
drush sql-dump > sites/default/files/backups/initial-db.sql


# final message
cat << EOF

Go to the project directory:
cd $PROJECT

Open the project in browser:
http://$PROJECT.dev/

EOF
