dbtools
=======

Set of simple db tools to (for example) easily deploy MongoDB (replicasets and sharding) or Galera Cluster for MySQL for your dev or test environment.

I'm using these scripts with my [lxctools][1] to quickly setup and tear down DB clusters on my lxc containers.

Hope it's useful for others as well.

Server Requirements
-------------------
- Passwordless ssh public key
- Passwordless sudo (unless root)  
  %sudo ALL=(ALL) NOPASSWD: ALL (Add your user to the sudo group)

- Galera Cluster: Min 3 DB nodes
- Galera ports: 3306, 4444, 4567, 4568

- Check your firewall/SELinux settings

Galera Cluster for MySQL
------------------------
Galera replication provides virtually synchrounous true multi-master replication for MySQL and is a great way to deploy a highly available MySQL cluster where there is no need for master failover and no slave lag!

NOTE: The boostrap script will wipeout any existing MySQL installation on the hosts.

Deploy a Galera Cluster
----------
<pre>
$ git clone git@github.com:alyu/dbtools.git
$ cd dbtools/galera
$ ./bootstrap-galera.sh
!! Running this Galera bootstrap will wipe out any current MySQL installation that you have on your hosts !!
Continue? (Y/n):
Download Galera packages (Y/n):
What is your OS on your DB nodes [ubuntu|redhat]: (ubuntu)
Galera MySQL tarball (https://launchpad.net/codership-mysql/5.5/5.5.23-23.6/+download/mysql-5.5.23_wsrep_23.6-linux-x86_64.tar.gz):
Galera wsrep library (https://launchpad.net/galera/2.x/23.2.1/+download/galera-23.2.1-amd64.deb):
Downloading packages...
Generate install scripts (Y/n):
MySQL install dir (/usr/local):
MySQL data dir (/usr/local/lib/mysql):
InnoDB buffer pools size (1G):
InnoDB log file size (1G):
Where are your Galera hosts () [ip1 ip2 ... ipN]: 10.0.3.140 10.0.3.150 10.0.3.160
Name your Galera Cluster (my_galera_cluster):
SST method [mysqldump|rsync|xtrabackup] (rsync):
Writeset slaves/parallel replication (1):
Generate tarball (Y/n):
SSH user (alex):
SSH pub key (/home/alex/.ssh/id_rsa.pub):
SSH port (22):
Creating tarball...
Deploy Galera (Y/n):
-- Bootstraping 10.0.3.140...
-- Installing wsrep provider library
-- Killing any MySQL server running...
...
-- 10.0.3.160 completed
Do you want to secure your Galera cluster (y/N): y
Enter a new MySQL root password: root123
Securing MySQL...
Galera Cluster for MySQL installed...
Done..0h:1m:52s
</pre>

[1]: https://github.com/alyu/lxctools

Deploy MongoDB Replicasets
--------------------------

Deploy MongoDB shards
---------------------
