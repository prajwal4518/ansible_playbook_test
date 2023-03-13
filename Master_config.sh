# install update to the system
echo 'About to update packages....'
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install jq -y
sudo apt-get -y install software-properties-common dirmngr apt-transport-https
sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mirrors.aliyun.com/mariadb/repo/10.2/ubuntu bionic main'
echo 'Successfully updated packages.'

CONFIG_FILE="/etc/mysql/my.cnf"
vault_token="s.g4o0uIVYM1RvmkwzPKrARo0R"
vault_url="http://10.99.24.4:8200/v1/kv/mariadb/test"
SLAVE_USERNAME=`curl -sS -H "X-Vault-Token: s.g4o0uIVYM1RvmkwzPKrARo0R" -X GET http://10.99.24.4:8200/v1/kv/mariadb/test | jq -r '.data.username'`
SLAVE_PASSWORD=`curl -sS -H "X-Vault-Token: ${vault_token}" -X GET ${vault_url} | jq -r '.data.password'`
SQL_ROOT_PASSWORD=`curl -sS -H "X-Vault-Token: ${vault_token}" -X GET ${vault_url} | jq -r '.data.password'`


# install MariaDB to the server
echo 'About to install MySQL....'
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${SQL_ROOT_PASSWORD}"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${SQL_ROOT_PASSWORD}"
sudo apt-get install mariadb-server -y
echo 'Successfully installed MySQL.'

# update the configuration file
echo 'Updating MySQL config in /etc/mysql/mariadb.conf.d/50-server.cnf....'
#update bind address, server-id and log_bin values
sudo sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" $CONFIG_FILE
sudo sed -i '/server-id/s/^#//g' $CONFIG_FILE
sudo sed -i '/log_bin/s/^#//g' $CONFIG_FILE
sudo service mariadb restart
echo 'Successfully updated MySQL config file'

# create a replication user
echo 'About to create user to be used for replication....'
sudo mysql -u "root" -p"${SQL_ROOT_PASSWORD}" -Bse "CREATE USER '${SLAVE_USERNAME}'@'%' identified by '${SLAVE_PASSWORD}';
GRANT REPLICATION slave, REPLICATION CLIENT ON *.* TO '${SLAVE_USERNAME}'@'%';"
echo 'Successfully created replication user'


# create_test_data
echo 'About to create data for testing replication....'
sudo mysql -u "root" -p"${SQL_ROOT_PASSWORD}" -Bse "CREATE DATABASE pets;
CREATE TABLE pets.dogs (name varchar(20));
INSERT INTO pets.dogs values ('fluffy');"
echo 'Successfully created replication test data'

# Taking backup of the test data
echo 'Taking backup of the test data....'
sudo mkdir -p /opt/mysql_backup
sudo mysqldump -u root -p$(curl -sS -H "X-Vault-Token: s.g4o0uIVYM1RvmkwzPKrARo0R" -X GET http://10.99.24.4:8200/v1/kv/mariadb/test | jq -r '.data.password') --all-databases --master-data=2 --single-transaction --events --routines --triggers --log-error=/opt/mysql_backup/backup.log --verbose > /opt/mysql_backup/all-db-backup.sql
echo 'Backup completed....'
