#!/bin/bash

# Update Galera Cluster for MySQL.
# Copyright (C) 2012  Alexander Yu <alex@alexyu.se>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

rel_dir=`dirname "$0"`
root_dir=`cd $rel_dir;pwd`
root_dir=${root_dir%/*}
echo "root_dir=$root_dir"
cd $root_dir/galera

shopt -s expand_aliases
alias sed="sed -i"
[[ $OSTYPE =~ ^darwin ]] && alias sed="sed -i ''"

installdir=/usr/local
datadir=/var/lib/mysql
mysql_service=mysql

os=ubuntu
user="$USER"
ssh_key="$HOME/.ssh/id_rsa.pub"
port=22

stagingdir=.stage
hosts=""
[ -e etc/config ] && . etc/config
[ -e $stagingdir/etc/hosts ] && hosts=($(cat $stagingdir/etc/hosts))

mysql_galera_dn="https://launchpad.net/codership-mysql/5.5/5.5.29-23.7.3/+download/mysql-5.5.29_wsrep_23.7.3-linux-x86_64.tar.gz"
wsrep_provider_dn="https://launchpad.net/galera/2.x/23.2.4/+download/galera-23.2.4-amd64.deb"
wsrep_provider_dn_redhat="https://launchpad.net/galera/2.x/23.2.4/+download/galera-23.2.4-1.rhel5.x86_64.rpm"

ask() {
  read -p "$1" x
  [ -z "$x" ] || [[ "$x" == ["$2${2^^}"] ]] && return 0
  return 1
}

download_packages() {
  read -p "What is your OS on your DB nodes [ubuntu|redhat]: ($os) " x
  [ ! -z $x ] && os=$x

  if [ "$os" == "redhat" ]
  then
    wsrep_provider_dn="$wsrep_provider_dn_redhat"
    wsrep_provider="$wsrep_provider_redhat"
    mysql_service=mysqld
  fi

  read -p "Galera MySQL tarball ($mysql_galera_dn): " x
  [ ! -z $x ] && mysql_galera_dn=$x

  read -p "Galera wsrep library ($wsrep_provider_dn): " x
  [ ! -z $x ] && wsrep_provider_dn=$x

  mysql_galera_tar=${mysql_galera_dn##*/}
  wsrep_provider_file=${wsrep_provider_dn##*/}

  echo "Downloading packages..."
  repo=$stagingdir/repo
  mkdir -p $repo
  [ ! -f "$repo/$mysql_galera_tar" ] && wget --tries=3 --no-check-certificate -O $repo/$mysql_galera_tar $mysql_galera_dn
  [ ! -f "$repo/$wsrep_provider_file" ] && wget --tries=3 --no-check-certificate -O $repo/$wsrep_provider_file $wsrep_provider_dn
}

gen_scripts() {
  read -p "MySQL install dir ($installdir): " x
  [ ! -z "$x" ] && installdir=$x

  basedir=$installdir/mysql
  echo "Setting MySQL base dir to $basedir"

  # generate scripts
  bindir=$stagingdir/bin
  mkdir -p $bindir

  cat > "$bindir/update_galera.sh" << EOF
#!/bin/bash

echo "*** Updating Galera wsrep provider"
os="$os"

root_dir=\$(dirname \$PWD/\$(dirname "\$BASH_SOURCE"))
if [ "\$os" == "ubuntu" ]
then
dpkg -r galera
dpkg -p galera
dpkg -i \$root_dir/repo/$wsrep_provider_file
apt-get -f install
else
yum -y remove galera
yum -y localinstall \$root_dir/repo/$wsrep_provider_file
fi
EOF

  cat > "$bindir/update_mysql_wsrep.sh" << EOF
#!/bin/bash

echo "*** Updating Galera MySQL"
rel_dir=`dirname "$0"`
root_dir=\$(dirname \$PWD/\$(dirname "\$BASH_SOURCE"))

mkdir -p $installdir
zcat \$root_dir/repo/$mysql_galera_tar | tar xf - -C $installdir
ln -sfn $installdir/${mysql_galera_tar%.tar.gz} $basedir

#service $mysql_service start "$@"

EOF

  chmod +x $bindir/*.sh

  read -p "Where are your Galera hosts (${hosts[*]}) [ip1 ip2 ... ipN]: " x
  [ ! -z "$x" ] && hosts=($x)
  [ -z "$x" ] && echo "Need some hosts..." && exit

  etcdir=$stagingdir/etc
  echo "${hosts[@]}" > $etcdir/hosts

  for h in ${hosts[*]}
  do
    ssh-keyscan -t rsa $h >> $HOME/.ssh/known_hosts
  done

  read -p "SSH user ($user): " x
  [ ! -z "$x" ] && user=$x

  read -p "SSH pub key ($ssh_key): " x
  [ ! -z "$x" ] && ssh_key=$x

  read -p "SSH port ($port): " x
  [ ! -z "$x" ] && port=$x

  sudo="sudo"
  [ $user == "root" ] && sudo=""
  cat > etc/config << EOF
os=$os
wsrep_cluster_address=$wsrep_cluster_address
ssh_key=$ssh_key
user=$user
port=$port
sudo=$sudo
installdir=$installdir
basedir=$basedir
datadir=$datadir
rundir=$rundir
innodb_buffer_pool_size=$innodb_buffer_pool_size
innodb_log_file_size=$innodb_log_file_size
mysql_galera_dn=$mysql_galera_dn
wsrep_provider_dn=$wsrep_provider_dn
mysql_galera_tar=${mysql_galera_dn##*/}
wsrep_provider_file=${wsrep_provider_dn##*/}
wsrep_provider=$wsrep_provider
wsrep_cluster_name=$wsrep_cluster_name
wsrep_sst_method=$wsrep_sst_method
wsrep_slave_threads=$wsrep_slave_threads
EOF

}

gen_tarball () {

  # make package
  echo "Creating tarball..."
  cd $stagingdir
  tar zcf galera.tgz repo bin
  cd ..
}

deploy_galera () {
  source etc/config

  cd $stagingdir
  hosts=$(cat etc/hosts)

  private_key=${ssh_key%.pub}
  hosts=($hosts)
  for (( i=0; i < ${#hosts[@]}; i++ ))
  do
    h=${hosts[$i]}
    echo "*** Updating $h..."
    scp -i $private_key -q -P $port galera.tgz $user@$h:~/
    cat > update.sh << EOF
mkdir -p ~/galera && zcat ~/galera.tgz | tar xf - -C ~/galera
$sudo galera/bin/update_galera.sh
$sudo galera/bin/update_mysql_wsrep.sh
EOF
    ssh -i $private_key -p $port $user@$h 'bash -s' < update.sh
    echo "*** $h completed"
  done
  rm -f update.sh

  cd ..
  echo "*** Galera Cluster for MySQL updated..."
}

# main
echo "!! Updating current MySQL Galera installation. Manual rolling restart needed. !!"
read -p "Continue? (Y/n): " x
[[ "$x" == ["nN"] ]] && exit 1

mkdir -p $stagingdir/etc
stime=$(date +'%s')

if ask "Download Galera packages (Y/n): " "y"
then
  download_packages
fi

if ask "Generate update scripts (Y/n): " "y"
then
  gen_scripts
fi

if ask "Generate distribution tarball (Y/n): " "y"
then
  gen_tarball
fi

if ask "Update Galera cluster (Y/n): " "y"
then
  deploy_galera
fi

etime=$(date +'%s')
secs=$((etime - stime))
printf ""%dh:%dm:%ds"\n" $(($secs/3600)) $(($secs%3600/60)) $(($secs%60))
