#MySQL:: Migrating ON-prem MySQL to RDS/Aurora with continuous replication

```
•Goal: To migrate/replicate between ON-PREMand RDS/Aurora with SSL enabled over VPN
•	Known Issues:
•	Setting up REPLICATION from On-prem (IHP) → RDS/AURORA (aka cutover)
o	On RDS/Aurora (Slave):
	0. Verify ACLs are open between AWS and ON-PREMfor port 3306.
	1. Create a new Aurora Instance
o	On-prem (Master): E2E302
	2. Create repl_aurora user with SSL enabled
	3. Generate CERTIFICATES
	4. Verify PERMISSIONS on CERTS and Ownership
	5. Enable SSL on On-Prem MySQL instance - my.cnf edits
	6. RESTART MySQL every time there is a change to CERTS and/or location
	7. Verify SSL is enabled using show variables and \s
	8. Verify that you can connect to AURORA as the replication user you created in STEP 2
	9. Verify that you can connect from any AWS host EC2 or Bastion host to IHP
	10. Verify you have connectivity to Aurora from IHP
	11. Get binlog position from On-prem (Master)
	12. Backup & Restore On-prem database on to Aurora - Materialization
	13. Verify DB copy was successful
	14. IMPORT certificates that you generated on On-prem (Master) → AURORA
	15.  Create replication channel from AURORA (Slave) to On-prem (Master)
	16. Verify replication threads are UP and running
	16(a). If you have to re-cyle/replace CERTS, do this
•	Setting up REPLICATION from RDS/AURORA → ON-PREM(On-prem)
o	17. Create the replication user repl_on-premuser on Aurora instance
o	18. Copy ca-bundle by region to ON-PREMhost & restart ON-PREMMySQL instance.
o	19. Verify connectivity of ihp_repl user from SLAVE (EC2 and On-Prem in this case)
o	20. Restart MySQL since certs have changed.
o	21. Create replication channel from ON-PREM(Slave) → RDS/AURORA (Master)
•	APPENDIX
•	Credits

Goal: To migrate/replicate between ON-PREMand RDS/Aurora with SSL enabled over VPN
This document applies to any team that is wanting to migrate their MySQL databases to RDS. This document focuses specifically on the "know how" on migrating a MySQL database to RDS-Aurora/MySQL. This is the future for all MySQL databases in Intuit as Aurora has some benefits that outweigh the features that are not available at this time. However, the features such as GTID support, Master/Master replication between regions will be available in December, 2018.

This document illustrates the STEPs that you need to take to ensure a successful migration to RDS/Aurora with minimal or no stress.
Known Issues:
We ran into a head-scratcher where we spent about 12 days trying to figure out why we weren't able to replicate using SSL over VPN while non-SSL worked just fine. It all came down to one thing - openssl version incompatibility.
For the sake of clarity I'll address this question directly:
1) If this OpenSSL library is packaged with MySQL version 5.6.36 and above then why is there a need to upgrading to OpenSSL 1.0.2k or newer on our On-prem servers?
1A) During the reproduction (and actual testing between On Prem Master > Aurora slave) we found that your On Prem MySQL server was utilizing OpenSSL 1.0.2j-fips which has proven to be incompatible with non-fips 1.0.2k in our testing (results in the same handshake failures we received). Prior to 5.6.36, MySQL was built utilizing older OpenSSL versions--but starting with version 5.6.36 MySQL, the linked OpenSSL library for the MySQL Commercial Server was updated to version 1.0.2k (Which should be Aurora compatible). I'll link Oracles release notes below for your convenience.[1] Otherwise, the only requirement is to ensure that you've upgraded OpenSSL to at least version 1.0.2k on your host. Also, I'd recommend that you have your MySQL database at 5.6.36 or higher.
```
# Setting up REPLICATION from On-prem (IHP) → RDS/AURORA (aka cutover)
On RDS/Aurora (Slave):
0. Verify ACLs are open between AWS and ON-PREMfor port 3306.
This is done by opening a CLOP-ticket to Cloud enable team (Chad Haney's team)
You will need to provide your VPC-ID, subnets etal.,
# Verify that you can connect from any AWS host EC2 or Bastion host
# Check connectivity between AWS and IHP
[root@ip-01-02-03-04~]# nc -z -w2 <onpremhostname> 3306
Connection to <onpremhostname> 3306 port [tcp/mysql] succeeded!

# Check connectivity between AWS and IHP
[root@<onpremhost>~]# nc -z -w2 -v 01.02.03.043306
Connection to 01.02.03.04 3306 port [tcp/mysql] succeeded!
#1. Create a new Aurora Instance
```
Instance: 		pocauroraslave
Endpoint: 		pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com
ClusterEndpoint:pocauroraslave.cluster-cairi4eiggpy.us-west-2.rds.amazonaws.com
secgrep: 		rds-launch-wizard-5 (sg-962acde5)
Subnets: 		subnet-aa4d98dc
      			subnet-6bc1720f
```

NOTE: make sure security group that is attached to RDS/Aurora has INBOUND rules allowing ON-PREMto connect on port 3306

On-prem (Master): E2E302
#2. Create repl_aurora user with SSL enabled
```
GRANT USAGE, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'repl_aurora'@'%' IDENTIFIED BY 'Start123!' REQUIRE SSL; flush privileges;
select user, host, super_priv, ssl_type, ssl_cipher from mysql.user order by 1;
mysql> show grants for repl_aurora@'%'\G
*************************** 1. row ***************************
Grants
 for repl_aurora@%: GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.*
TO 'repl_aurora'@'%' IDENTIFIED BY PASSWORD
'*7AF464F8D2AB879A68182B56C7A67810FC94BD90' REQUIRE SSL
NOTE:
# To enable/disable SSL later
UPDATE mysql.user SET ssl_type = 'any' WHERE user = 'repl_aurora' ; FLUSH PRIVILEGES;
# To disable for repl_aurora run this
grant usage on *.* to repl_aurora@'%' require NONE;
```
#3. Generate CERTIFICATES
```
WARNING: CN has to be unique between all certs (Example: CA, CAServer CAClient )
*** NOTE: CN has to be unique between all certs (Example: CA, CAServer CAClient )
--------------
openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 365 -key ca-key.pem -out ca.pem
openssl req -newkey rsa:2048 -days 365 -nodes -keyout server-key.pem -out server-req.pem
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 365 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
openssl req -newkey rsa:2048 -days 365 -nodes -keyout client-key.pem -out client-req.pem
openssl rsa -in client-key.pem -out client-key.pem
openssl x509 -req -in client-req.pem -days 365 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out client-cert.pem
openssl verify -CAfile ca.pem server-cert.pem client-cert.pem
-------------
930  09/08/18 11:57:25  cd ssl
  931  09/08/18 11:57:37  openssl genrsa 2048 > ca-key.pem
  932  09/08/18 11:57:59  ll
  933  09/08/18 11:58:02  openssl req -new -x509 -nodes -days 365 -key ca-key.pem -out ca.pem
  934  09/08/18 12:00:38  ll
  935  09/08/18 12:00:52  openssl req -newkey rsa:2048 -days 365 -nodes -keyout server-key.pem -out server-req.pem
  936  09/08/18 12:01:29  ll
  937  09/08/18 12:02:01  openssl rsa -in server-key.pem -out server-key.pem
  938  09/08/18 12:02:03  ll
  939  09/08/18 12:02:16  openssl x509 -req -in server-req.pem -days 365 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
  940  09/08/18 12:02:19  ll
  941  09/08/18 12:03:00  openssl req -newkey rsa:2048 -days 365 -nodes -keyout client-key.pem -out client-req.pem
  942  09/08/18 12:03:25  ll
  943  09/08/18 12:03:37  openssl rsa -in client-key.pem -out client-key.pem
  944  09/08/18 12:03:40  ll
  945  09/08/18 12:03:51  openssl x509 -req -in client-req.pem -days 365 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out client-cert.pem
  946  09/08/18 12:03:53  ll

[root@<onpremhost>ssl]# ll
total 32
-rw-r--r-- 1 root  root  1679 Aug  9 11:57 ca-key.pem
-rw-r--r-- 1 root  root  1285 Aug  9 12:00 ca.pem
lrwxrwxrwx 1 mysql mysql   16 Jun 27 17:32 certs -> ../pki/tls/certs
-rw-r--r-- 1 root  root  1168 Aug  9 12:03 client-cert.pem
-rw-r--r-- 1 root  root  1675 Aug  9 12:03 client-key.pem
-rw-r--r-- 1 root  root   997 Aug  9 12:03 client-req.pem
-rw-r--r-- 1 root  root  1168 Aug  9 12:02 server-cert.pem
-rw-r--r-- 1 root  root  1675 Aug  9 12:02 server-key.pem
-rw-r--r-- 1 root  root   997 Aug  9 12:01 server-req.pem
```
#4. Verify PERMISSIONS on CERTS and Ownership

```
# After generating the certificates, verify them:
openssl verify -CAfile ca.pem server-cert.pem client-cert.pem

[root@<onpremhost>ssl]# openssl verify -CAfile ca.pem server-cert.pem client-cert.pem
server-cert.pem: OK
client-cert.pem: OK

# VALIDATE Server and Client CERTS by running these
-- Start openssl server
openssl s_server -cert /etc/ssl/server-cert.pem -key /etc/ssl/server-key.pem -www &

# Verity CA
openssl s_client -CAfile /etc/ssl/ca.pem -connect 127.0.0.1:4433

# Now, kill ssl server
[root@<onpremhost>ssl]# ps -ef|grep s_server
root     28185 12384  0 12:11 pts/0    00:00:00 openssl s_server -cert /etc/ssl/server-cert.pem -key /etc/ssl/server-key.pem -www
root     28582 12384  0 12:12 pts/0    00:00:00 grep s_server
[root@<onpremhost>ssl]# kill -9 28185
[root@<onpremhost>ssl]# ps -ef|grep s_server
root     28781 12384  0 12:12 pts/0    00:00:00 grep s_server
[1]+  Killed                  openssl s_server -cert /etc/ssl/server-cert.pem -key /etc/ssl/server-key.pem -www

# change ownership to mysql user
[root@<onpremhost>etc]# pwd
/etc
[root@<onpremhost>etc]# ls -ld
drwxr-xr-x. 117 root root 12288 Aug 15 01:18 .

# chown -R mysql:mysql /etc/ssl/*.pem
# chmod 400 /etc/ssl/*.pem
# chown -R mysql:mysql /etc/ssl

[root@<onpremhost>etc]# ls -ltr ssl
total 28
lrwxrwxrwx 1 mysql mysql   16 Jun 27 17:32 certs -> ../pki/tls/certs
drwxr-xr-x 2 root  root  4096 Aug 10 13:34 56certs
-r-------- 1 mysql mysql 1298 Aug 10 13:46 ca.pem
-r-------- 1 mysql mysql 1176 Aug 10 13:46 client-cert.pem
-r-------- 1 mysql mysql 1675 Aug 10 13:46 client-key.pem
-r-------- 1 mysql mysql 1176 Aug 10 13:46 server-cert.pem
-r-------- 1 mysql mysql 1679 Aug 10 13:46 server-key.pem
-r-------- 1 mysql mysql  997 Aug 10 13:46 server-req.pem

# OPTIONAL - list contents of CERTS
openssl x509 -text -in ca.pem
openssl x509 -text -in server-cert.pem
openssl x509 -text -in client-cert.pem
```
#5. Enable SSL on On-Prem MySQL instance - my.cnf edits
```
# -----------------------------------
# SSL Client
# -----------------------------------
ssl-ca=/etc/ssl/ca.pem
ssl-cert=/etc/ssl/client-cert.pem
ssl-key=/etc/ssl/client-key.pem

# -----------------------------------
# SSL Server
# -----------------------------------
ssl-ca=/etc/ssl/ca.pem
ssl-cert=/etc/ssl/server-cert.pem
ssl-key=/etc/ssl/server-key.pem
```
#6. RESTART MySQL every time there is a change to CERTS and/or location
```
# service mysql restart
```
#7. Verify SSL is enabled using show variables and \s

```
NOTE: You should see CIPHER in use
+---------------+--------------------------+
| Variable_name | Value                    |
+---------------+--------------------------+
| have_openssl  | YES                      |
| have_ssl      | YES                      |
| ssl_ca        | /etc/ssl/ca.pem          |
| ssl_capath    |                          |
| ssl_cert      | /etc/ssl/server-cert.pem |
| ssl_cipher    |                          |
| ssl_crl       |                          |
| ssl_crlpath   |                          |
| ssl_key       | /etc/ssl/server-key.pem  |
+---------------+--------------------------+
mysql> \s
--------------
mysql  Ver 14.14 Distrib 5.6.24, for Linux (x86_64) using  EditLine wrapper

Connection id:        28
Current database:
Current user:        root@localhost
SSL:            Cipher in use is DHE-RSA-AES256-SHA
Current pager:        stdout
Using outfile:        ''
Using delimiter:    ;
Server version:        5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)
Protocol version:    10
Connection:        Localhost via UNIX socket
Server characterset:    latin1
Db     characterset:    latin1
Client characterset:    latin1
Conn.  characterset:    latin1
UNIX socket:        /var/lib/mysql/mysql.sock
Uptime:            3 min 48 sec

Threads: 1  Questions: 116  Slow queries: 0  Opens: 169  Flush tables: 1  Open tables: 162  Queries per second avg: 0.508
--------------
```
#8. Verify that you can connect to AURORA as the replication user you created in STEP 2
```
[root@<onpremhost>ssl]# mysql -u repl_aurora -h localhost --ssl-cert=/etc/ssl/client-cert.pem --ssl-key=/etc/ssl/client-key.pem  --ssl=true -p
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 9357
Server version: 5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)

Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> exit

Option #2: Using CA cert
[root@<onpremhost>ssl]# mysql -h localhost -urepl_aurora --ssl=true -p --ssl-ca=ca.pem
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 9393
Server version: 5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)

Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> exit

[root@<onpremhost>ssl]# mysql -h <onpremhostname> -urepl_aurora --ssl=true -p --ssl-ca=ca.pem
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 9392
Server version: 5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)

Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> exit


This should work!
```
#9. Verify that you can connect from any AWS host EC2 or Bastion host to IHP
```
# Check connectivity between AWS and IHP
[root@ip-01-02-03-04~]# nc -z -w2 <onpremhostname> 3306
Connection to <onpremhostname> 3306 port [tcp/mysql] succeeded!

# Check connectivity between AWS and IHP
# STEP1: Copy certs from ON-PREMto AWS host
mtvl1535b8a01:~cnappoly:/Users/cnappoly/Downloads$ scp cnappoly-admin@pe2evdldb302:/tmp/*.pem .

# Get Session keys and profile name ready to copy to S3

# STEP2: Copy to S3
mtvl1535b8a01:~cnappoly:/Users/cnappoly/Downloads$ aws s3 cp ca.pem s3://<s3bucketname>/ --profile poc_preprod
upload: ./ca.pem to s3://<s3bucketname>/ca.pem
mtvl1535b8a01:~cnappoly:/Users/cnappoly/Downloads$ aws s3 cp client-cert.pem  s3://<s3bucketname>/ --profile poc_preprod
upload: ./client-cert.pem to s3://<s3bucketname>/client-cert.pem
mtvl1535b8a01:~cnappoly:/Users/cnappoly/Downloads$ aws s3 cp client-key.pem  s3://<s3bucketname>/ --profile poc_preprod
upload: ./client-key.pem to s3://<s3bucketname>/client-key.pem

mtvl1535b8a01:~cnappoly:/Users/cnappoly/Downloads$ aws s3 ls <s3bucketname> --profile poc_preprod
2018-08-08 14:22:14   18723880 MySQL-client-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 14:21:19   65974428 MySQL-server-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 14:30:28    2031048 MySQL-shared-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 14:30:50    3945168 MySQL-shared-compat-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-09 14:09:17       1285 ca.pem
2018-08-09 14:09:31       1168 client-cert.pem
2018-08-09 14:09:47       1675 client-key.pem
2018-08-08 10:30:07       1696 govi.pem

# STEP3: Download from S3 to AWS host (Ec2)
ec2-user@ip-01-02-03-04~]$ aws s3 ls <s3bucketname>
2018-08-08 21:22:14   18723880 MySQL-client-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 21:21:19   65974428 MySQL-server-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 21:30:28    2031048 MySQL-shared-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-08 21:30:50    3945168 MySQL-shared-compat-advanced-5.6.24-1.el6.x86_64.rpm
2018-08-09 21:09:17       1285 ca.pem
2018-08-09 21:09:31       1168 client-cert.pem
2018-08-09 21:09:47       1675 client-key.pem
2018-08-08 17:30:07       1696 govi.pem

[ec2-user@ip-01-02-03-04~]$ aws s3 cp s3://<s3bucketname>/ca.pem .
download: s3://<s3bucketname>/ca.pem to ./ca.pem
[ec2-user@ip-01-02-03-04~]$ aws s3 cp s3://<s3bucketname>/client-cert.pem .
download: s3://<s3bucketname>/client-cert.pem to ./client-cert.pem
[ec2-user@ip-01-02-03-04~]$ aws s3 cp s3://<s3bucketname>/client-key.pem .
download: s3://<s3bucketname>/client-key.pem to ./client-key.pem

# STEP4: Connect from EC2 using repl_aurora
[ec2-user@ip-01-02-03-04~]$ mysql -h <onpremhostname> -urepl_aurora --ssl=true -p --ssl-ca=ca.pem
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 208
Server version: 5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)

Copyright (c) 2000, 2018, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> select current_user();
+----------------+
| current_user() |
+----------------+
| repl_aurora@%  |
+----------------+
1 row in set (0.04 sec)

# Now verify Client Certs
[ec2-user@ip-01-02-03-04~]$ mysql -h <onpremhostname> -urepl_aurora --ssl=true -p --ssl-cert=client-cert.pem --ssl-key=client-key.pem
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 218
Server version: 5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)

Copyright (c) 2000, 2018, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> \s
--------------
mysql  Ver 14.14 Distrib 5.6.41, for Linux (x86_64) using  EditLine wrapper

Connection id:        218
Current database:
Current user:        repl_aurora@10.84.183.91
SSL:            Cipher in use is DHE-RSA-AES256-SHA
Current pager:        stdout
Using outfile:        ''
Using delimiter:    ;
Server version:        5.6.24-enterprise-commercial-advanced-log MySQL Enterprise Server - Advanced Edition (Commercial)
Protocol version:    10
Connection:        <onpremhostname> via TCP/IP
Server characterset:    latin1
Db     characterset:    latin1
Client characterset:    utf8
Conn.  characterset:    utf8
TCP port:        3306
Uptime:            35 min 12 sec

Threads: 1  Questions: 930  Slow queries: 0  Opens: 169  Flush tables: 1  Open tables: 162  Queries per second avg: 0.440
--------------
```
#10. Verify you have connectivity to Aurora from IHP
```
[root@<onpremhost>tmp]# mysql -u pocadmin-h pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com -p --ssl=false
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 10
Server version: 5.6.10-log MySQL Community Server (GPL)

Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> select current_user();
+----------------+
| current_user() |
+----------------+
| pocadmin@%     |
+----------------+
1 row in set (0.04 sec)
```
#11. Get binlog position from On-prem (Master)
```
[root@<onpremhost>tmp]# mysql --login-path=admin
Welcome to the MySQL monitor.  Commands end with ; or \g.
Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> show master status\G
*************************** 1. row ***************************
             File: mysql-bin.000027
         Position: 271
     Binlog_Do_DB:
 Binlog_Ignore_DB: information_schema,performance_schema,mysql,quartz
Executed_Gtid_Set: 26e100e4-3261-11e4-90b5-005056851b5c:1-4,
4ea5b366-6be3-11e4-87b6-005056854d94:1-15,
f64b9325-6a1b-11e4-bc1c-0050569f0b4c:1-22082
1 row in set (0.00 sec)

NOTE: Make sure you disable GTID on Master since Aurora "does not" support GTID yet.
```
#12. Backup & Restore On-prem database on to Aurora - Materialization
```
# Backup using Non-SSL
[root@<onpremhost>tmp]# mysqldump --login-path=admin --databases poc --set-gtid-purged=OFF --single-transaction --compress --routines --triggers --events --order-by-primary  --ssl=false | mysql -u pocadmin-h pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com -ppocadmin--ssl=false

# Backup using SSL ON
mysqldump --login-path=admin --databases poc_metrics --set-gtid-purged=OFF --single-transaction --compress --routines --triggers --events --order-by-primary  --ssl=true --ssl-ca=/etc/ssl/ca.pem | mysql -u pocadmin-h pocauroraslave.cluster-cairi4eiggpy.us-west-2.rds.amazonaws.com -ppocadmin--ssl=true --ssl-ca=/rdsdbdata/sslreplication/ssl_ca.pem

```
#13. Verify DB copy was successful
```
 mysql> \s
--------------
mysql  Ver 14.14 Distrib 5.6.24, for Linux (x86_64) using  EditLine wrapper

Connection id:        22
Current database:    poc
Current user:        pocadmin@on-prem
SSL:            Not in use
Current pager:        stdout
Using outfile:        ''
Using delimiter:    ;
Server version:        5.6.10-log MySQL Community Server (GPL)
Protocol version:    10
Connection:        pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com via TCP/IP
Server characterset:    latin1
Db     characterset:    utf8
Client characterset:    latin1
Conn.  characterset:    latin1
TCP port:        3306
Uptime:            30 min 9 sec

Threads: 6  Questions: 13456  Slow queries: 0  Opens: 304  Flush tables: 1  Open tables: 221  Queries per second avg: 7.438
--------------

mysql> SELECT table_schema "Data Base Name",  sum( data_length + index_length ) / 1024 / 1024 "Data Base Size in MB",  sum( data_free )/ 1024 / 1024 "Free Space in MB"  FROM information_schema.TABLES  GROUP BY table_schema;
+--------------------+----------------------+------------------+
| Data Base Name     | Data Base Size in MB | Free Space in MB |
+--------------------+----------------------+------------------+
| information_schema |           0.01171875 |       0.00000000 |
| mysql              |           8.63836956 |    2170.00000000 |
| performance_schema |           0.00000000 |       0.00000000 |
| poc                |         145.92187500 |      42.00000000 |
+--------------------+----------------------+------------------+
4 rows in set (0.05 sec)
```
#14. IMPORT certificates that you generated on On-prem (Master) → AURORA
NOTE: use the template to fill in the keys
https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/mysql_rds_import_binlog_ssl_material.html
```
CALL mysql.rds_import_binlog_ssl_material (
'{"ssl_ca":"-----BEGIN CERTIFICATE-----
-----END CERTIFICATE-----\n","ssl_cert":"-----BEGIN CERTIFICATE-----
-----END CERTIFICATE-----\n","ssl_key":"-----BEGIN RSA PRIVATE KEY-----
-----END RSA PRIVATE KEY-----\n"}'
);
+-------------------------------+
| Message                       |
+-------------------------------+
| SSL material import complete. |
+-------------------------------+
1 row in set (0.09 sec)
```
#15.  Create replication channel from AURORA (Slave) to On-prem (Master)
```
NOTE: mysql> CALL mysql.rds_set_external_master ('<Hostname> or <IP address>', 3306,'repl_aurora', 'Start123!', 'mysql-bin.000032', 194, 1);

mysql> CALL mysql.rds_set_external_master ('on-prem', 3306,'repl_aurora', 'Start123!', 'mysql-bin.000032', 194, 1);
Query OK, 0 rows affected (0.19 sec)

mysql> show slave status\G
*************************** 1. row ***************************
               Slave_IO_State:
                  Master_Host: on-prem
                  Master_User: repl_aurora
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000027
          Read_Master_Log_Pos: 271
               Relay_Log_File: relaylog.000001
                Relay_Log_Pos: 4
        Relay_Master_Log_File: mysql-bin.000027
             Slave_IO_Running: No
            Slave_SQL_Running: No
              Replicate_Do_DB:
          Replicate_Ignore_DB:
           Replicate_Do_Table:
       Replicate_Ignore_Table: mysql.rds_replication_status,mysql.rds_monitor,mysql.rds_sysinfo,mysql.rds_configuration,mysql.rds_history
      Replicate_Wild_Do_Table:
  Replicate_Wild_Ignore_Table:
                   Last_Errno: 0
                   Last_Error:
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 271
              Relay_Log_Space: 120
              Until_Condition: None
               Until_Log_File:
                Until_Log_Pos: 0
           Master_SSL_Allowed: Yes
           Master_SSL_CA_File: /rdsdbdata/sslreplication/ssl_ca.pem
           Master_SSL_CA_Path:
              Master_SSL_Cert: /rdsdbdata/sslreplication/ssl_cert.pem
            Master_SSL_Cipher:
               Master_SSL_Key: /rdsdbdata/sslreplication/ssl_key.pem
        Seconds_Behind_Master: NULL
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error:
               Last_SQL_Errno: 0
               Last_SQL_Error:
  Replicate_Ignore_Server_Ids:
             Master_Server_Id: 0
                  Master_UUID:
             Master_Info_File: mysql.slave_master_info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State:
           Master_Retry_Count: 86400
                  Master_Bind:
      Last_IO_Error_Timestamp:
     Last_SQL_Error_Timestamp:
               Master_SSL_Crl: /rdsdbdata/sslreplication/ssl_ca.pem
           Master_SSL_Crlpath:
           Retrieved_Gtid_Set:
            Executed_Gtid_Set:
                Auto_Position: 0
1 row in set (0.04 sec)

Start slave using CALL mysql.rds_start_replication;

mysql> CALL mysql.rds_start_replication;
+-------------------------+
| Message                 |
+-------------------------+
| Slave running normally. |
+-------------------------+
1 row in set (1.05 sec)

Query OK, 0 rows affected (1.05 sec)
```
#16. Verify replication threads are UP and running
```
2018-08-09 22:31:05 7005 [Note] Slave SQL thread initialized, starting replication in log 'mysql-bin.000027' at position 271, relay log '/rdsdbdata/log/relaylog/relaylog.000001' position: 4
2018-08-09 22:31:05 7005 [ERROR] Slave I/O: error connecting to master 'repl_aurora@on-prem:3306' - retry-time: 60 retries: 1, Error_code: 2026
2018-08-09 22:31:08 7005 [Note] Error reading relay log event: slave SQL thread was killed
2018-08-09 22:31:08 7005 [Note] Slave I/O thread killed while connecting to master
2018-08-09 22:31:08 7005 [Note] Slave I/O thread exiting, read up to log 'mysql-bin.000027', position 271
2018-08-09 22:31:09 7005 [Warning] Storing MySQL user name or password information in the master info repository is not secure and is therefore not recommended. Please consider using the USER and PASSWORD connection options for START SLAVE; see the 'START SLAVE Syntax' in the MySQL Manual for more information.


***NOTE: If you get the above error set binlog retention. https://forums.aws.amazon.com/thread.jspa?threadID=164599

# Set binlog retention
# Verify retention
mysql> call mysql.rds_show_configuration;
+------------------------+-------+------------------------------------------------------------------------------------------------------+
| name                   | value | description                                                                                          |
+------------------------+-------+------------------------------------------------------------------------------------------------------+
| binlog retention hours | NULL  | binlog retention hours specifies the duration in hours before binary logs are automatically deleted. |
+------------------------+-------+------------------------------------------------------------------------------------------------------+
1 row in set (0.04 sec)

# Set binlog retention
mysql> CALL mysql.rds_set_configuration('binlog retention hours', 144);
Query OK, 0 rows affected (0.04 sec)


mysql> show slave status\G
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: on-prem
                  Master_User: repl_aurora
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin.000038
          Read_Master_Log_Pos: 1079
               Relay_Log_File: relaylog.000314
                Relay_Log_Pos: 236
        Relay_Master_Log_File: mysql-bin.000038
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB:
          Replicate_Ignore_DB:
           Replicate_Do_Table:
       Replicate_Ignore_Table: mysql.rds_replication_status,mysql.rds_monitor,mysql.rds_sysinfo,mysql.rds_configuration,mysql.rds_history
      Replicate_Wild_Do_Table:
  Replicate_Wild_Ignore_Table:
                   Last_Errno: 0
                   Last_Error:
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 1079
              Relay_Log_Space: 518
              Until_Condition: None
               Until_Log_File:
                Until_Log_Pos: 0
           Master_SSL_Allowed: Yes
           Master_SSL_CA_File: /rdsdbdata/sslreplication/ssl_ca.pem
           Master_SSL_CA_Path:
              Master_SSL_Cert: /rdsdbdata/sslreplication/ssl_cert.pem
            Master_SSL_Cipher:
               Master_SSL_Key: /rdsdbdata/sslreplication/ssl_key.pem
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error:
               Last_SQL_Errno: 0
               Last_SQL_Error:
  Replicate_Ignore_Server_Ids:
             Master_Server_Id: 4
                  Master_UUID: 4ea5b366-6be3-11e4-87b6-005056854d94
             Master_Info_File: mysql.slave_master_info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State: Slave has read all relay log; waiting for the slave I/O thread to update it
           Master_Retry_Count: 86400
                  Master_Bind:
      Last_IO_Error_Timestamp:
     Last_SQL_Error_Timestamp:
               Master_SSL_Crl: /rdsdbdata/sslreplication/ssl_ca.pem
           Master_SSL_Crlpath:
           Retrieved_Gtid_Set:
            Executed_Gtid_Set:
                Auto_Position: 0
1 row in set (0.02 sec)

REPLICATION WORKS!!!
```
##16(a). If you have to re-cyle/replace CERTS, do this
```
(a). STOP slaves/ RESET slave and reconfigure replication
mysql> CALL mysql.rds_stop_replication; CALL mysql.rds_reset_external_master;
+---------------------------+
| Message                   |
+---------------------------+
| Slave is down or disabled |
+---------------------------+
1 row in set (1.05 sec)

Query OK, 0 rows affected (1.05 sec)

+----------------------+
| message              |
+----------------------+
| Slave has been reset |
+----------------------+
1 row in set (0.12 sec)

Query OK, 0 rows affected (0.12 sec)

(b). Remove existing CERTS
mysql> CALL mysql.rds_remove_binlog_ssl_material;
Query OK, 0 rows affected (0.04 sec)

# Reimport certs using
CALL mysql.rds_import_binlog_ssl_material
(
'{"ssl_ca":"-----BEGIN CERTIFICATE-----
ssl_ca_pem_body_code
-----END CERTIFICATE-----\n","ssl_cert":"-----BEGIN CERTIFICATE-----
ssl_cert_pem_body_code
-----END CERTIFICATE-----\n","ssl_key":"-----BEGIN RSA PRIVATE KEY-----
ssl_key_pem_body_code
-----END RSA PRIVATE KEY-----\n"}'
);

# RESTART AURORA

# Start replication
mysql> CALL mysql.rds_start_replication;

mysql> show slave status\G
```
# Setting up REPLICATION from RDS/AURORA  (On-prem)
#17. Create the replication user repl_on-premuser on Aurora instance
NOTE: This is the user ON-PREM MySQL (SLAVE) will use to CONNECT to AURORA (MASTER)
```
aurora-mysql> GRANT USAGE, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'repl_ihp'@'%' IDENTIFIED BY 'Start123!' REQUIRE SSL; flush privileges; select user, host, super_priv, ssl_type, ssl_cipher from mysql.user order by 1; show grants for repl_ihp@'%'\G
```
#18. Copy ca-bundle by region to ON-PREM host & restart ON-PREMMySQL instance.
Refernce: URL: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
```
# VERIFY permissions and ownership of pem files to be 400 and mysql.
# cd /etc/ssl
# wget 'https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem'

If you want to use region-specific bundle pem, get it from here (below)
wget 'https://s3.amazonaws.com/rds-downloads/rds-ca-2015-us-west-2.pem'

NOTE: IF THE ABOVE Cert doesn't work, one of the reasons could be that it doesn't have all the contents of CA, SERVER and CLIENT cert. So,do the following:

# Get root and combined certs if region certificate doesn't work.
NOTE: Combine them into one file rds-ca-2015-root.pem
[root@ip-01-02-03-04ssl]# wget https://s3.amazonaws.com/rds-downloads/rds-ca-2015-root.pem
--2018-08-27 18:27:44--  https://s3.amazonaws.com/rds-downloads/rds-ca-2015-root.pem
Resolving s3.amazonaws.com... 52.216.32.51
Connecting to s3.amazonaws.com|52.216.32.51|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 1432 (1.4K) [binary/octet-stream]
Saving to: “rds-ca-2015-root.pem”

100%[=====================================================================================================================================>] 1,432       --.-K/s   in 0s

2018-08-27 18:27:45 (85.0 MB/s) - “rds-ca-2015-root.pem” saved [1432/1432]

[root@ip-01-02-03-04ssl]# wget 'https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem';
--2018-08-27 18:27:50--  https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem
Resolving s3.amazonaws.com... 54.231.83.18
Connecting to s3.amazonaws.com|54.231.83.18|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 26016 (25K) [binary/octet-stream]
Saving to: “rds-combined-ca-bundle.pem”

100%[=====================================================================================================================================>] 26,016      --.-K/s   in 0.08s

2018-08-27 18:27:50 (326 KB/s) - “rds-combined-ca-bundle.pem” saved [26016/26016]

[root@ip-01-02-03-04ssl]# !ls
ls -larth
total 60K
-rw-------.   1 root  root  1.4K Mar  7  2015 rds-ca-2015-root.pem
lrwxrwxrwx.   1 root  root    16 Jan 18  2018 certs -> ../pki/tls/certs
-rw-------.   1 root  root   26K May 21 16:39 rds-combined-ca-bundle.pem
-rw-------.   1 mysql mysql 1.7K Aug 16 01:44 client-key.pem
-rw-------.   1 mysql mysql 1.2K Aug 16 01:44 client-cert.pem
-rw-------.   1 mysql mysql 1.3K Aug 16 01:44 ca.pem
drwxr-xr-x. 101 root  root   12K Aug 24 04:40 ..
drwxr-xr-x.   2 root  root  4.0K Aug 27 18:27 .


# COMBINE them into one file
Copy the contents of rds-combined-ca-bundle.pem to the beginning of rds-ca-2015-root.pem file.
Basically, copying the intermediate cert to the TOP of the root certificate.
OR
Copy root cert to the bottom of rds-combined-ca-bundle.pem file.
```
#19. Verify connectivity of ihp_repl user from SLAVE (EC2 and On-Prem in this case)
```
[root@<onpremhost>ssl]# mysql -u repl_on-prem-hpocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com --ssl-verify-server-cert --ssl-ca=/etc/ssl/rds-ca-2015-root.pem -p
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 9951
Server version: 5.6.10-log MySQL Community Server (GPL)

Copyright (c) 2000, 2018, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> select user();
+-----------------------+
| user()                |
+-----------------------+
| repl_ihp@on-prem |
+-----------------------+
1 row in set (0.01 sec)

mysql> \s
--------------
mysql  Ver 14.14 Distrib 5.6.41, for Linux (x86_64) using  EditLine wrapper

Connection id:        9951
Current database:
Current user:        repl_ihp@on-prem
SSL:            Cipher in use is DHE-RSA-AES256-SHA
Current pager:        stdout
Using outfile:        ''
Using delimiter:    ;
Server version:        5.6.10-log MySQL Community Server (GPL)
Protocol version:    10
Connection:        pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com via TCP/IP
Server characterset:    latin1
Db     characterset:    latin1
Client characterset:    latin1
Conn.  characterset:    latin1
TCP port:        3306
Uptime:            10 days 21 hours 14 min 58 sec

Threads: 8  Questions: 6778767  Slow queries: 0  Opens: 180  Flush tables: 1  Open tables: 166  Queries per second avg: 7.207
--------------
```
#20. Restart MySQL since certs have changed.
```
[root@<onpremhost>ssl]# service mysql restart
Shutting down MySQL.. SUCCESS!
Starting MySQL... SUCCESS!
```
#21. Create replication channel from ON-PREM(Slave) → RDS/AURORA (Master)
NOTE: This is done so that we can replicate back to ON-PREMfrom AWS
```
mysql> stop slave; reset slave all;
Query OK, 0 rows affected (0.01 sec)

Query OK, 0 rows affected (0.02 sec)

mysql> show slave status\G
Empty set (0.00 sec)

mysql> CHANGE MASTER TO
    -> MASTER_HOST='pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com',
    -> MASTER_USER='repl_ihp',
    -> MASTER_PASSWORD='Start123!',
    -> MASTER_LOG_FILE='mysql-bin-changelog.000008',
    -> MASTER_LOG_POS=2228,
    -> MASTER_SSL_CA = '/etc/ssl/rds-ca-2015-root.pem',
    -> MASTER_SSL=1;
Query OK, 0 rows affected, 2 warnings (0.11 sec)

# Verify replication works
mysql> start slave; select sleep(2); show slave status\G
Query OK, 0 rows affected (0.01 sec)

+----------+
| sleep(2) |
+----------+
|        0 |
+----------+
1 row in set (2.00 sec)

*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: pocauroraslave.cairi4eiggpy.us-west-2.rds.amazonaws.com
                  Master_User: repl_ihp
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: mysql-bin-changelog.000008
          Read_Master_Log_Pos: 2228
               Relay_Log_File: mysql-relay-bin.000002
                Relay_Log_Pos: 293
        Relay_Master_Log_File: mysql-bin-changelog.000008
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB:
          Replicate_Ignore_DB:
           Replicate_Do_Table:
       Replicate_Ignore_Table:
      Replicate_Wild_Do_Table:
  Replicate_Wild_Ignore_Table:
                   Last_Errno: 0
                   Last_Error:
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 2228
              Relay_Log_Space: 466
              Until_Condition: None
               Until_Log_File:
                Until_Log_Pos: 0
           Master_SSL_Allowed: Yes
           Master_SSL_CA_File: /etc/ssl/rds-ca-2015-root.pem
           Master_SSL_CA_Path:
              Master_SSL_Cert:
            Master_SSL_Cipher:
               Master_SSL_Key:
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error:
               Last_SQL_Errno: 0
               Last_SQL_Error:
  Replicate_Ignore_Server_Ids:
             Master_Server_Id: 1246967466
                  Master_UUID: 475b873d-2912-36de-8005-726da23e8e26
             Master_Info_File: /data/mysql/master.info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State: Slave has read all relay log; waiting for the slave I/O thread to update it
           Master_Retry_Count: 86400
                  Master_Bind:
      Last_IO_Error_Timestamp:
     Last_SQL_Error_Timestamp:
               Master_SSL_Crl:
           Master_SSL_Crlpath:
           Retrieved_Gtid_Set:
            Executed_Gtid_Set: 26e100e4-3261-11e4-90b5-005056851b5c:1-4,
4ea5b366-6be3-11e4-87b6-005056854d94:1-18,
f64b9325-6a1b-11e4-bc1c-0050569f0b4c:1-22082
                Auto_Position: 0
1 row in set (0.00 sec)
```
# APPENDIX
```
# Backup using SSL ON
mysqldump --login-path=admin --databases poc_metrics --set-gtid-purged=OFF --single-transaction --compress --routines --triggers --events --order-by-primary  --ssl=true --ssl-ca=/etc/ssl/ca.pem | mysql -u pocadmin-h pocauroraslave.cluster-cairi4eiggpy.us-west-2.rds.amazonaws.com -ppocadmin--ssl=true --ssl-ca=/rdsdbdata/sslreplication/ssl_ca.pem

#----------------------------------
TCPDUMP script
#----------------------------------
#!/bin/bash
#start a process in the background (it happens to be a TCP HTTP sniffer on  the loopback interface, for my apache server):
tcpdump -i lo -w dump.pcap 'port 80' &

#.....other commands that send packets to tcpdump.....
#now interrupt the process.  get its PID:
pid=$(ps -e | pgrep tcpdump)
echo $pid

#interrupt it:
kill -2 $pid
```

# CREDITS
```
This effort would not have been possible without the help and collaboration from these folks below:
Govi Vanakuru - for his tenacity and resolve and not giving up
Maitrayee Shah - For sharing their journey to RDS/MySQL for FDP and her help with Cloud-formation
Chad Haney/James Norton - Support with ACLs and troubleshooting OpenSSL issue from Intuit's perspective
Aurora Engineering Team & Support team - For not giving up on openSSL and nailing the issue with OpenSSL linked libraries.
```
