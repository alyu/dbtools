#!/bin/bash

# Bootstrap Galera Cluster for MySQL.
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
datadir=/usr/local/lib/mysql
rundir=/var/run/mysqld
innodb_buffer_pool_size=2G
innodb_log_file_size=1G
my_cnf=etc/my.cnf
mysql_service=mysql
stop_fw="service ufw stop"
stop_fw_redhat="service iptables stop"

wsrep_cluster_name=my_galera_cluster
wsrep_sst_method=rsync
wsrep_slave_threads=1

os=ubuntu
user="$USER"
ssh_key=/home/ubuntu/.ssh/id_rsa.pub
port=22

stagingdir=.stage
hosts=""
[ -e etc/config ] && . etc/config
[ -e $stagingdir/etc/hosts ] && hosts=($(cat $stagingdir/etc/hosts))

mysql_galera_dn="https://launchpad.net/codership-mysql/5.5/5.5.28-23.7/+download/mysql-5.5.28_wsrep_23.7-linux-x86_64.tar.gz"
wsrep_provider_dn="https://launchpad.net/galera/2.x/23.2.2/+download/galera-23.2.2-amd64.deb"
wsrep_provider_dn_redhat="https://launchpad.net/galera/2.x/23.2.2/+download/galera-23.2.2-1.rhel5.x86_64.rpm"
xtra_packages="libssl0.9.8 psmisc libaio1 rsync netcat wget"
xtra_packages_redhat="openssl psmisc libaio rsync nc wget"
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_provider_redhat=/usr/lib64/galera/libgalera_smm.so
[ $user != "root" ] && ssh_key=/home/$user/.ssh/id_rsa.pub

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
    xtra_packages="$xtra_packages_redhat"
    wsrep_provider="$wsrep_provider_redhat"
    stop_fw="$stop_fw_redhat"
    [ $user != "root" ] && user=root && ssh_key=/root/.ssh/id_rsa.pub
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

  read -p "MySQL data dir ($datadir): " x
  [ ! -z "$x" ] && datadir=$x

  read -p "InnoDB buffer pool size ($innodb_buffer_pool_size): " x
  [ ! -z "$x" ] && innodb_buffer_pool_size=$x

  read -p "InnoDB log file size ($innodb_log_file_size): " x
  [ ! -z "$x" ] && innodb_log_file_size=$x

  # modify my.cnf
  etcdir=$stagingdir/etc
  sed "s|^basedir.*=*|basedir = $installdir/mysql|g" $etcdir/my.cnf
  sed "s|^datadir.*=*|datadir = $datadir|g" $etcdir/my.cnf
  sed "s|^innodb_buffer_pool_size.*=*|innodb_buffer_pool_size = $innodb_buffer_pool_size|" $etcdir/my.cnf
  sed "s|^innodb_log_file_size.*=*|innodb_log_file_size = $innodb_log_file_size|" $etcdir/my.cnf

  # generate scripts
  bindir=$stagingdir/bin
  mkdir -p $bindir

  cat > "$bindir/install_wsrep.sh" << EOF
#!/bin/bash

echo "*** Installing Galera wsrep provider"
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

  cat > "$bindir/install_mysql_galera.sh" << EOF
#!/bin/bash

echo "*** Installing Galera MySQL"
os="$os"

rel_dir=`dirname "$0"`

root_dir=\$(dirname \$PWD/\$(dirname "\$BASH_SOURCE"))
echo "Killing any MySQL server running..."
killall -9 mysqld_safe mysqld rsync
echo "Wiping datadir and existing my.cnf files..."
rm -rf $datadir/*
rm -rf /etc/my.cnf /etc/mysql

mkdir -p $installdir
rm -rf $installdir/${mysql_galera_tar%.tar.gz}
if [ "\$os" == "ubuntu" ]
then
apt-get -y remove --purge mysql-server mysql-client mysql-common
apt-get -y autoremove
apt-get -y autoclean
apt-get -y --force-yes install $xtra_packages
else
yum -y remove mysql mysql-libs mysql-devel mysql-server mysql-bench
yum -y install $xtra_packages
fi

zcat \$root_dir/repo/$mysql_galera_tar | tar xf - -C $installdir
ln -sf $installdir/${mysql_galera_tar%.tar.gz} $basedir

cp -f \$root_dir/etc/my.cnf /etc/
cp -f $basedir/support-files/mysql.server /etc/init.d/$mysql_service
mkdir -p $datadir

# mysql user
\$(id mysql) &> /dev/null
if [ \$? -eq 1 ]
then
  echo "Creating mysql user..."
  groupadd -r mysql
  useradd -r -M -g mysql mysql
fi
$basedir/scripts/mysql_install_db --no-defaults --basedir=$basedir --datadir=$datadir
chown -R mysql.mysql $datadir
mkdir -p $rundir
chown mysql $rundir

if [ "\$os" == "ubuntu" ]
then
# disable apparmor
[ -d /etc/apparmor.d ] && ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disabled/usr.sbin.mysqld &> /dev/null
else
# disable SELinux
command -v setenforce &>/dev/null && setenforce 0
fi

sysctl -w vm.swappiness=0
echo "vm.swappiness = 0" | sudo tee -a /etc/sysctl.conf &> /dev/null

$stop_fw &> /dev/null

service $mysql_service start "$@"

EOF

  chmod +x $bindir/*.sh

  read -p "Where are your Galera hosts (${hosts[*]}) [ip1 ip2 ... ipN]: " x
  [ ! -z "$x" ] && hosts=($x)

  etcdir=$stagingdir/etc
  echo "${hosts[@]}" > $etcdir/hosts

  for h in ${hosts[*]}
  do
    ssh-keyscan -t rsa $h >> $HOME/.ssh/known_hosts
  done

  IFS_DEF=$IFS
  IFS=","
  wsrep_cluster_address="gcomm://${hosts[*]}"
  IFS=$IFS_DEF

  sed "s|^.*wsrep_cluster_address.*=.*|wsrep_cluster_address = $wsrep_cluster_address|" $etcdir/my.cnf
  sed "s|^wsrep_provider.*=.*|wsrep_provider = $wsrep_provider|" $etcdir/my.cnf

  read -p "Name your Galera Cluster ($wsrep_cluster_name): " x
  [ ! -z $x ] && wsrep_cluster_name=$x

  read -p "SST method [rsync|xtrabackup] ($wsrep_sst_method): " x
  [ ! -z $x ] && wsrep_sst_method=$x

  read -p "Writeset slaves/parallel replication ($wsrep_slave_threads): " x
  [ ! -z $x ] && wsrep_slave_threads=$x

  sed "s|^wsrep_cluster_name.*=.*|wsrep_cluster_name = $wsrep_cluster_name|" $etcdir/my.cnf
  sed "s|^wsrep_sst_method.*=.*|wsrep_sst_method = $wsrep_sst_method|" $etcdir/my.cnf
  sed "s|^wsrep_slave_threads.*=.*|wsrep_slave_threads = $wsrep_slave_threads|" $etcdir/my.cnf

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
  tar zcf galera.tgz repo etc bin
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
    echo "*** Bootstraping $h..."
    command -v ssh-copy-id &>/dev/null && ssh-copy-id -i $private_key "$user@$h -p $port" &> /dev/null
    scp -i $private_key -q -P $port galera.tgz $user@$h:~/
    ssh -i $private_key -t -p $port $user@$h 'mkdir -p ~/galera && zcat ~/galera.tgz | tar xf - -C ~/galera'
    if (( $i == 0))
    then
      # first node, initialize the cluster
      echo "*** Initializing cluster... "
      ssh -i $private_key -t -p $port $user@$h "sed -i \"s|^.*wsrep_node_address.*=.*|wsrep_node_address = $h|\" ~/galera/etc/my.cnf"
      ssh -i $private_key -t -p $port $user@$h "$sudo galera/bin/install_mysql_galera.sh --wsrep-cluster-address='gcomm://'"
      # give the instance some time to start up
      sleep 5
    else
      ssh -i $private_key -t -p $port $user@$h "$sudo galera/bin/install_mysql_galera.sh"
    fi
    echo "*** $h completed"
  done

  read -p "Do you want to secure your Galera cluster (y/N): " x
  if [[ "$x" == ["yY"] ]]
  then
    read -p "Enter a new MySQL root password: " x
    cat > "secure.sql" << EOF
UPDATE mysql.user SET Password=PASSWORD('$x') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE DB='test' OR DB='test\\_%';
FLUSH PRIVILEGES;
EOF
    h=${hosts[0]}
    echo "*** Securing MySQL ($h)..."
    scp -i $private_key -q -P $port secure.sql $user@$h:~/
    ssh -i $private_key -t -p $port $user@$h "$basedir/bin/mysql -uroot -h127.0.0.1 < ~/secure.sql; $sudo rm ~/secure.sql"
  fi

  cd ..
  echo "*** Galera Cluster for MySQL installed..."
}

# main
echo "!! Running this Galera bootstrap will wipe out any current MySQL installation that you have on your hosts !!"
read -p "Continue? (Y/n): " x
[[ "$x" == ["nN"] ]] && exit 1

mkdir -p $stagingdir/etc
cp $my_cnf $stagingdir/etc/

stime=$(date +'%s')

if ask "Download Galera packages (Y/n): " "y"
then
  download_packages
fi

if ask "Generate install scripts and my.cnf file (Y/n): " "y"
then
  gen_scripts
fi

if ask "Generate distribution tarball (Y/n): " "y"
then
  gen_tarball
fi

if ask "Deploy Galera cluster (Y/n): " "y"
then
  deploy_galera
fi

etime=$(date +'%s')
secs=$((etime - stime))
printf ""%dh:%dm:%ds"\n" $(($secs/3600)) $(($secs%3600/60)) $(($secs%60))
