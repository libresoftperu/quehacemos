#!/bin/bash -e

# GUEST IP
GUEST_IP=192.168.88.88

# Hosts files
HOSTS=/etc/hosts

# Edit the following to change the name of the database user that will be created:
APP_DB_USER=node
APP_DB_PASS=node8088

# Node version duh
NODE_VER=5.x

# Edit the following to change the version of PostgreSQL that is installed
PG_VERSION=9.5

# Edit the following to change the name of the database that is created (defaults to the user name)
APP_DB_NAME=$APP_DB_USER



# TODO: change the print usage text
###########################################################
# Changes below this line are probably not necessary
###########################################################
print_db_usage () {
  echo "Your NODEJS environment has been setup"
  echo "  Host: $GUEST_IP  [ local.qhacemos ]"
  echo "  Guest IP: $GUEST_IP"
  echo "    added:   \"local.qhacemos   $GUEST_IP\"   to /etc/hosts"
  echo ""
  echo "  NodeJS v:$NODE_VER"
  echo ""
  echo "  Port: 5432"
  echo "  Database: $APP_DB_NAME"
  echo "  Username: $APP_DB_USER"
  echo "  Password: $APP_DB_PASS"
  echo ""
  echo "Admin access to postgres user via VM:"
  echo "  vagrant ssh"
  echo "  sudo su - postgres"
  echo ""
  echo "psql access to app database user via VM:"
  echo "  vagrant ssh"
  echo "  sudo su - postgres"
  echo "  PGUSER=$APP_DB_USER PGPASSWORD=$APP_DB_PASS psql -h localhost $APP_DB_NAME"
  echo ""
  echo "Env variable for application development:"
  echo "  DATABASE_URL=postgresql://$APP_DB_USER:$APP_DB_PASS@*:5432/$APP_DB_NAME"
  echo ""
  echo "Local command to access the database via psql:"
  echo "  PGUSER=$APP_DB_USER PGPASSWORD=$APP_DB_PASS psql -h localhost -p 5432 $APP_DB_NAME"
  echo ""
  echo "  Getting into the box (terminal):"
  echo "  vagrant ssh"
  echo "  sudo su - postgres"
  echo ""
}

export DEBIAN_FRONTEND=noninteractive

PROVISIONED_ON=/etc/vm_provision_on_timestamp
if [ -f "$PROVISIONED_ON" ]
then
  echo "VM was already provisioned at: $(cat $PROVISIONED_ON)"
  echo "To run system updates manually login via 'vagrant ssh' and run 'apt-get update && apt-get upgrade'"
  echo ""
  print_db_usage
  exit
fi

chown vagrant /etc/hosts
echo "$GUEST_IP   local.qhacemos" >> /etc/hosts

PG_REPO_APT_SOURCE=/etc/apt/sources.list.d/pgdg.list
if [ ! -f "$PG_REPO_APT_SOURCE" ]
then
  # Add PG apt repo:
  echo "deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main" > "$PG_REPO_APT_SOURCE"

  # Add PGDG repo key:
  wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add -
fi

# update / upgrade
apt-get update
#apt-get -y upgrade #too slow - instead, keep the virtual box up-to-date

# get gyp dependency for binary versions (faster)
apt-get -y install build-essential
apt-get -y install python
#apt-get install python-setuptools
apt-get -y install gyp

# install node
#apt-get -y install curl
curl -sL "https://deb.nodesource.com/setup_$NODE_VER" | sudo -E bash -
sudo apt-get install -y nodejs

#Install node-inspector package for debugging
npm install -g node-inspector

# install git
sudo apt-get -y install git


# Install standard version of postgresql
#apt-get -y install "postgresql-$PG_VERSION" "postgresql-contrib-$PG_VERSION"

# Install dev version of postgresql to support debugging
apt-get -y install "postgresql-server-dev-$PG_VERSION"  "postgresql-contrib-$PG_VERSION"

PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_DIR="/var/lib/postgresql/$PG_VERSION/main"


# Edit postgresql.conf to change listen address to '*':
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# Edit postgresql.conf to add shared_preload_libraries
sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'plugin_debugger'/" "$PG_CONF"


# Clone and build the PL/pgSQL server-side debugger
cd /usr/local/src
git clone git://git.postgresql.org/git/pldebugger.git
cd pldebugger
export USE_PGXS=1
make
make install

# install pgxn client
#easy_install pgxnclient


# Append to pg_hba.conf to add password auth:
echo "host    all             all             all                     md5" >> "$PG_HBA"


# We need to add password aouth for $APP_DB_USER before other aouth configs.
match='# "local" is for Unix domain socket connections only'
insert="local    all             $APP_DB_USER                           md5"
sed -i "s/$match/$match\n$insert/" $PG_HBA


# Restart so that all new config is loaded:
service postgresql restart

cat << EOF | su - postgres -c psql
-- Create the database user:
CREATE USER $APP_DB_USER WITH PASSWORD '$APP_DB_PASS';

-- Create the database:
CREATE DATABASE $APP_DB_NAME WITH OWNER $APP_DB_USER;


-- auto explain for analyse all queries and inside functions
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 0;
SET auto_explain.log_analyze = true;

EOF



# db deploy scripts
echo "deploy base db with sample data"
# db base deploy version 0.1.0
cd /home/vagrant/quehacemos/scripts/deploy-dev
chmod a+x deploy.sh
mkdir -p log
./deploy.sh 2> log/deploydb.log



# Restart PostgreSQL for good measure
service postgresql restart



# Tag the provision time:
date > "$PROVISIONED_ON"

echo "Successfully created NODE.JS 5 dev virtual machine with Postgres"
echo ""
print_db_usage
