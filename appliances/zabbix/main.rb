# frozen_string_literal: true

begin
    require '/etc/one-appliance/lib/helpers'
rescue LoadError
    require_relative '../lib/helpers'
end

require_relative 'config'


# Base module for OpenNebula services
module Service

    # Zabbix appliance implmentation
    module Zabbix

        extend self

        DEPENDS_ON    = []

        def install
            msg :info, 'Zabbix::install'
            install_repo
            install_zabbix
            msg :info, 'Installation completed successfully'
        end

        def configure
            msg :info, 'Zabbix::configure'
            update_zabbix_conf
            create_database
            start_zabbix
            msg :info, 'Configuration completed successfully'
        end

        def bootstrap
            msg :info, 'Zabbix::bootstrap'
        end
    end

    def install_repo
        # repository for Zabbix
        puts bash <<~SCRIPT
            wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
            dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
            apt-get update
        SCRIPT
    end

    def install_zabbix
        # installs Zabbix and dependencies
        puts bash "apt-get install -y zabbix-server-pgsql zabbix-frontend-php php8.3-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent postgresql"
    end

    def create_database
        msg :info, 'Creating Zabbix database...'
        if database_exists?
            msg :info, 'Database already exists, continuing'
            return
        end

        unless !ONEAPP_ZABBIX_DB_PASSWORD.empty?
            raise "Error: ONEAPP_ZABBIX_DB_PASSWORD not defined"
        end

        msg :info, 'Configuring PostgreSQL for Zabbix database access...'

        pg_version = `ls /etc/postgresql/ 2>/dev/null | grep -E '^[0-9]+$' | sort -rV | head -n 1`.strip
        if pg_version.empty?
            raise "Error: Could not determine PostgreSQL version. Please set it manually."
        end
        pg_hba_conf_path = "/etc/postgresql/#{pg_version}/main/pg_hba.conf"

        # Backup pg_hba.conf
        puts bash "sudo cp #{pg_hba_conf_path} #{pg_hba_conf_path}.bak"

        puts bash <<~HBA_SCRIPT
            set -e

            MD5_ENTRY="local   #{ONEAPP_ZABBIX_DB_NAME}      #{ONEAPP_ZABBIX_DB_USER}          md5"

            if ! grep -qF "$MD5_ENTRY" #{pg_hba_conf_path}; then
                if grep -qE "^local\\s+#{ONEAPP_ZABBIX_DB_NAME}\\s+#{ONEAPP_ZABBIX_DB_USER}\\s+peer" #{pg_hba_conf_path}; then
                    sudo sed -i "s/^local\\s\\+#{ONEAPP_ZABBIX_DB_NAME}\\s\\+#{ONEAPP_ZABBIX_DB_USER}\\s\\+peer/$MD5_ENTRY/" #{pg_hba_conf_path}
                    echo "Replaced existing 'peer' entry for Zabbix with 'md5'."
                else
                    if grep -qE "^local\\s+all\\s+all\\s+peer" #{pg_hba_conf_path}; then
                        sudo awk -v insert="$MD5_ENTRY" '/^local\\s+all\\s+all\\s+peer/ && !inserted { print insert; inserted=1 } { print }' #{pg_hba_conf_path} > /tmp/pg_hba.conf.tmp && sudo mv /tmp/pg_hba.conf.tmp #{pg_hba_conf_path}
                        echo "Inserted new 'md5' entry before 'local all all peer'."
                    else
                        echo "$MD5_ENTRY" | sudo tee -a #{pg_hba_conf_path}
                        echo "Appended new 'md5' entry as a fallback."
                    fi
                fi
            else
                echo "'md5' entry for Zabbix already exists."
            fi
        HBA_SCRIPT

        msg :info, 'Restarting PostgreSQL service and waiting for it to be ready...'
        puts bash <<~RESTART_WAIT_SCRIPT
            sudo systemctl restart postgresql
            ATTEMPTS=0
            MAX_ATTEMPTS=30
            SLEEP_TIME=2 # seconds

            while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
                if sudo -u postgres pg_isready -q -h /var/run/postgresql -p 5432; then
                    echo "PostgreSQL is ready!"
                    break
                fi
                echo "Waiting for PostgreSQL to start... (Attempt $((ATTEMPTS+1)) of $MAX_ATTEMPTS)"
                sleep $SLEEP_TIME
                ATTEMPTS=$((ATTEMPTS+1))
            done

            if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
                echo "Error: PostgreSQL did not become ready in time." >&2
                exit 1
            fi
        RESTART_WAIT_SCRIPT

        puts bash <<~SCRIPT
            sudo -u postgres psql -c "CREATE USER #{ONEAPP_ZABBIX_DB_USER} WITH PASSWORD '#{ONEAPP_ZABBIX_DB_PASSWORD}';"
            sudo -u postgres createdb -O #{ONEAPP_ZABBIX_DB_USER} #{ONEAPP_ZABBIX_DB_NAME};

            zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u postgres PGPASSWORD='#{ONEAPP_ZABBIX_DB_PASSWORD}' psql -d #{ONEAPP_ZABBIX_DB_NAME} -U #{ONEAPP_ZABBIX_DB_USER}
        SCRIPT
        msg :info, 'Database created and initial schema imported'
    end

    def update_zabbix_conf
        msg :info, 'Updating zabbix_server.conf and nginx.conf files...'
        unless File.exist?("#{ZABBIX_SERVER_CONF}")
            raise "Error: Zabbix server configuration file not found at '#{ZABBIX_SERVER_CONF}'."
        end

        begin
            zabbix_conf_file = File.read("#{ZABBIX_SERVER_CONF}")
            nginx_conf_file = File.read("#{ZABBIX_NGINX_CONF}")

            zabbix_conf_file = zabbix_conf_file.gsub(/^(\s*)#?\s*(DBPassword=.*$)/, "\\1\\2'#{ONEAPP_ZABBIX_DB_PASSWORD}'")

            nginx_conf_file = nginx_conf_file.gsub(/^(\s*)#?\s*listen\s+\d+;/, "\\1listen #{ONEAPP_ZABBIX_PORT};")
            nginx_conf_file = nginx_conf_file.gsub(/^(\s*)#?\s*server_name\s+[^;]+;/, "\\1server_name #{ONEAPP_ZABBIX_SERVER_NAME};")

            File.write("#{ZABBIX_SERVER_CONF}", zabbix_conf_file)
            File.write("#{ZABBIX_NGINX_CONF}", nginx_conf_file)
            msg :info, 'Zabbix configuration files updated...'
        rescue => e
            raise "Error updating Zabbix server configuration file: #{e.message}"
        end
    end

    def start_zabbix
        msg :info, 'Starting and enabling Zabbix...'
        puts bash <<~SCRIPT
            systemctl restart zabbix-server zabbix-agent nginx php8.3-fpm
            systemctl enable zabbix-server zabbix-agent nginx php8.3-fpm
        SCRIPT
    end

    def database_exists?
        `sudo su postgres -c 'psql -l | grep zabbix | wc -l'`.strip.to_i > 0
    end
end
