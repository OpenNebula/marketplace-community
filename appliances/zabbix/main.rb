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

        puts bash <<~SCRIPT
            sudo -u postgres psql -c "CREATE USER #{ONEAPP_ZABBIX_DB_USER} WITH PASSWORD '#{ONEAPP_ZABBIX_DB_PASSWORD}';"
            sudo -u postgres createdb -O #{ONEAPP_ZABBIX_DB_USER} #{ONEAPP_ZABBIX_DB_NAME};

            zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u #{ONEAPP_ZABBIX_DB_USER} psql #{ONEAPP_ZABBIX_DB_NAME}
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
