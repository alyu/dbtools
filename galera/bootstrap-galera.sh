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

installdir=/usr/local
datadir=/var/lib/mysql
rundir=/var/run/mysqld
innodb_buffer_pool_size=2G
innodb_log_file_size=1G
my_cnf=etc/my.cnf
mysql_service=mysql
stop_fw="service ufw stop"

wsrep_cluster_name=my_galera_cluster
wsrep_sst_method=rsync
wsrep_slave_threads=1

os=ubuntu
user=ubuntu
ssh_key=/home/ubuntu/.ssh/id_rsa.pub
port=22

hosts=""
[ -e etc/config ] && . etc/config
[ -e etc/hosts ] && hosts=`cat etc/hosts`

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
    wsrep_provider_dn="https://launchpad.net/codership-mysql/5.5/5.5.28-23.7/+download/MySQL-server-5.5.28_wsrep_23.7-1.rhel5.x86_64.rpm"
    wsrep_provider_file=${wsrep_provider_dn##*/}
    xtra_packages="openssl psmisc libaio rsync nc wget"
    wsrep_provider=/usr/lib64/galera/libgalera_smm.so
    stop_fw="service iptables stop"
    [ $user != "root" ] && user=root && ssh_key=/root/.ssh/id_rsa.pub
  else
    mysql_galera_dn="https://launchpad.net/codership-mysql/5.5/5.5.28-23.7/+download/mysql-5.5.28_wsrep_23.7-linux-x86_64.tar.gz"
    wsrep_provider_dn="https://launchpad.net/galera/2.x/23.2.2/+download/galera-23.2.2-amd64.deb"
    xtra_packages="libssl0.9.8 psmisc libaio1 rsync netcat wget"
    wsrep_provider=/usr/lib/galera/libgalera_smm.so
    [ $user != "root" ] && ssh_key=/home/$user/.ssh/id_rsa.pub
  fi

  read -p "Galera MySQL tarball ($mysql_galera_dn): " x
  [ ! -z $x ] && mysql_galera_dn=$x

  read -p "Galera wsrep library ($wsrep_provider_dn): " x
  [ ! -z $x ] && wsrep_provider_dn=$x

  mysql_galera_tar=${mysql_galera_dn##*/}
  wsrep_provider_file=${wsrep_provider_dn##*/}

  echo "Downloading packages..."

  mkdir -p repo
  [ ! -f "repo/$mysql_galera_tar" ] && wget --tries=3 --no-check-certificate -O repo/$mysql_galera_tar $mysql_galera_dn
  [ ! -f "repo/$wsrep_provider_file" ] && wget --tries=3 --no-check-certificate -O repo/$wsrep_provider_file $wsrep_provider_dn
}

gen_scripts() {
  read -p "MySQL install dir ($installdir): " x
  [ ! -z "$x" ] && installdir=$x

  basedir=$installdir/mysql

  read -p "MySQL data dir ($datadir): " x
  [ ! -z "$x" ] && datadir=$x

  read -p "InnoDB buffer pools size ($innodb_buffer_pool_size): " x
  [ ! -z "$x" ] && innodb_buffer_pool_size=$x

  read -p "InnoDB log file size ($innodb_log_file_size): " x
  [ ! -z "$x" ] && innodb_log_file_size=$x

  # modify my.cnf
  sed -i "s|^basedir.*=*|basedir = $installdir/mysql|g" $my_cnf
  sed -i "s|^datadir.*=*|datadir = $datadir|g" $my_cnf
  sed -i "s|^innodb_buffer_pool_size.*=*|innodb_buffer_pool_size = $innodb_buffer_pool_size|" $my_cnf
  sed -i "s|^innodb_log_file_size.*=*|innodb_log_file_size = $innodb_log_file_size|" $my_cnf

  # generate scripts
  mkdir -p bin

  cat > "bin/install_wsrep.sh" << EOF
#!/bin/bash
os="$os"

#rel_dir=`dirname "$0"`
#root_dir=`cd $rel_dir;pwd`
#root_dir=${root_dir%/*}
root_dir=\$(dirname \$PWD/\$(dirname "\$BASH_SOURCE"))
echo "-- Killing any MySQL server running..."
killall -9 mysqld mysqld_safe > /dev/null 2>&1
echo "Wiping datadir and existing my.cnf files..."
rm -rf $datadir/*
rm -rf /etc/my.cnf /etc/mysql
if [ "\$os" == "ubuntu" ]
then
apt-get -y remove --purge mysql-server mysql-client mysql-common ${wsrep_provider_file%.*} &> /dev/null
apt-get -y autoremove
apt-get -y autoclean
apt-get -y --force-yes install $xtra_packages
dpkg -i \$root_dir/repo/$wsrep_provider_file
apt-get -f install
else
yum -y remove mysql mysql-libs mysql-devel mysql-server mysql-bench ${wsrep_provider_file%.*} &> /dev/null
yum -y install $xtra_packages
yum -y localinstall \$root_dir/repo/$wsrep_provider_file
fi
#rm -rf ${wsrep_provider%/*}
EOF

  cat > "bin/install_mysql_galera.sh" << EOF
#!/bin/bash
rel_dir=`dirname "$0"`
#root_dir=`cd $rel_dir;pwd`
#root_dir=${root_dir%/*}
root_dir=\$(dirname \$PWD/\$(dirname "\$BASH_SOURCE"))
echo "-- Killing any MySQL server running..."
#service $mysql_service stop > /dev/null 2>&1
killall -9 mysqld mysqld_safe > /dev/null 2>&1
echo "Wiping datadir and existing my.cnf files..."
rm -rf $datadir/*
mkdir -p $installdir
rm -rf $installdir/${mysql_galera_tar%.tar.gz}
zcat \$root_dir/repo/$mysql_galera_tar | tar xf - -C $installdir
# remove symlink
rm -f $basedir
ln -sf $installdir/${mysql_galera_tar%.tar.gz} $basedir
h=(\$(hostname -I))
sed -i "s|^wsrep_node_address.*=*|wsrep_node_address = \${h[1]}|" \$root_dir/$my_cnf

cp -f \$root_dir/etc/my.cnf /etc/
cp -f $basedir/support-files/mysql.server /etc/init.d/$mysql_service
mkdir -p $datadir

# mysql user
\`id mysql > /dev/null 2>&1\`
if [ \$? -eq 1 ]
then
  echo "Creating mysql user..."
  groupadd -r mysql
  useradd -r -M -g mysql mysql
fi
$basedir/scripts/mysql_install_db --no-defaults --basedir=$basedir --datadir=$datadir
chown -R mysql.mysql $datadir > /dev/null 2>&1
chown mysql $rundir > /dev/null 2>&1

# disable apparmor
ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disabled/usr.sbin.mysqld > /dev/null 2>&1
# rhel/SELinux, ignore error on debian/ubuntu
setenforce 0 > /dev/null 2>&1

sudo sysctl -w vm.swappiness=0
echo "vm.swappiness = 0" | sudo tee -a /etc/sysctl.conf

$stop_fw

service $mysql_service start > /dev/null 2>&1

EOF

  chmod +x bin/*.sh

  wsrep_urls=""
  read -p "Where are your Galera hosts ($hosts) [ip1 ip2 ... ipN]: " x
  [ ! -z "$x" ] && hosts="$x"

  echo "${hosts[@]}" > etc/hosts

  for h in $hosts
  do
    wsrep_urls+="gcomm://$h:4567,"
    ssh-keyscan -t rsa $h >> $HOME/.ssh/known_hosts
  done
  wsrep_urls=${wsrep_urls%,}

  sed -i "s|^wsrep_urls.*=*|wsrep_urls = $wsrep_urls|" $my_cnf
  sed -i "s|^wsrep_provider.*=*|wsrep_provider = $wsrep_provider|" $my_cnf

  read -p "Name your Galera Cluster ($wsrep_cluster_name): " x
  [ ! -z $x ] && wsrep_cluster_name=$x

  read -p "SST method [mysqldump|rsync|xtrabackup] ($wsrep_sst_method): " x
  [ ! -z $x ] && wsrep_sst_method=$x

  read -p "Writeset slaves/parallel replication ($wsrep_slave_threads): " x
  [ ! -z $x ] && wsrep_slave_threads=$x

  sed -i "s|^wsrep_cluster_name.*=*|wsrep_cluster_name = $wsrep_cluster_name|" $my_cnf
  sed -i "s|^wsrep_sst_method.*=*|wsrep_sst_method = $wsrep_sst_method|" $my_cnf
  sed -i "s|^wsrep_slave_threads.*=*|wsrep_slave_threads = $wsrep_slave_threads|" $my_cnf
}

gen_tarball () {
  read -p "SSH user ($user): " x
  [ ! -z "$x" ] && user=$x

  read -p "SSH pub key ($ssh_key): " x
  [ ! -z "$x" ] && ssh_key=$x

  read -p "SSH port ($port): " x
  [ ! -z "$x" ] && port=$x

  # make package
  echo "Creating tarball..."
  rm -f etc/config
  tar zcvf galera.tgz repo etc bin &> /dev/null

  sudo=sudo
  [ $user == "root" ] && sudo=""
  cat > etc/config << EOF
os=$os
wsrep_url=$wsrep_urls
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

deploy_galera () {
  hosts=`cat etc/hosts`
  . etc/config

  private_key=${ssh_key%.pub}
  hosts=($hosts)
  init_urls="gcomm://"

  for (( i=0; i < ${#hosts[@]}; i++ ))
  do
    h=${hosts[$i]}
	echo "-- Bootstraping $h..."
	scp -i $private_key -q -P $port galera.tgz $user@$h:~/
    {
	  #[ -f $ssh_key ] && ssh -i $private_key -t -p $port $user@$h 'cat >> ~/.ssh/authorized_keys' < $ssh_key
	  echo "mkdir -p ~/galera && zcat ~/galera.tgz | tar xf - -C ~/galera"
	  if (( $i == 0))
	  then
	  # first node, initialize the cluster
		echo "sed -i.org 's|^wsrep_urls.*=*|wsrep_urls = $init_urls|' ~/galera/etc/my.cnf"
	  fi
	  echo "echo -- Installing wsrep provider library"
	  echo "galera/bin/install_wsrep.sh"
	  echo "echo -- Installing Galera for MySQL"
	  echo "galera/bin/install_mysql_galera.sh"
	  if (( $i == 0 ))
	  then
		# revert back wsrep_urls for first node
		echo "cp -f ~/galera/etc/my.cnf.org /etc/my.cnf"
	  fi
	  # give the instance some time to come up
	  sleep 5
	  echo "rm -rf galera*"
	  echo "echo -- $h completed"
    } | ssh -i $private_key -t -p $port $user@$h "$sudo bash -s"
  done

  read -p "Do you want to secure your Galera cluster (y/N): " x
  if [[ "$x" == ["yY"] ]]
  then
    read -p "Enter a new MySQL root password: " x
    cat > "secure.sql" << EOF
UPDATE mysql.user SET Password=PASSWORD('$x') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE test; DELETE FROM mysql.db WHERE DB='test' OR DB='test\\_%';
FLUSH PRIVILEGES;
EOF
    echo "Securing MySQL..."
    h=${hosts[0]}
    scp -i $private_key -q -P $port secure.sql $user@$h:~/
    ssh -i $private_key -t -p $port $user@$h "$basedir/bin/mysql -uroot -h127.0.0.1 < ~/secure.sql ; rm -f secure.sql"
  fi

  echo "Galera Cluster for MySQL installed..."
}

# main
echo "!! Running this Galera bootstrap will wipe out any current MySQL installation that you have on your hosts !!"
read -p "Continue? (Y/n): " x
[[ "$x" == ["nN"] ]] && exit 1

stime=$(date +'%s')

ask "Download Galera packages (Y/n): " "y" && download_packages

ask "Generate install scripts (Y/n): " "y" && gen_scripts

ask "Generate deployment tarball (Y/n): " "y" && gen_tarball

ask "Deploy Galera (Y/n): " "y" && deploy_galera

etime=$(date +'%s')
secs=$((etime - stime))
printf "Done...%dh:%dm:%ds\n" $(($secs/3600)) $(($secs%3600/60)) $(($secs%60))
