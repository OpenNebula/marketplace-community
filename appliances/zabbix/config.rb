# frozen_string_literal: true

begin
    require '/etc/one-appliance/lib/helpers'
rescue LoadError
    require_relative '../lib/helpers'
end

ZABBIX_SERVER_CONF = "/etc/zabbix/zabbix_server.conf"
ZABBIX_NGINX_CONF = "/etc/zabbix/nginx.conf"

# These variables are not exposed to the user and only used during install
ONEAPP_ZABBIX_RELEASE_VERSION = env :ONEAPP_ZABBIX_RELEASE_VERSION, '7.0'

# Zabbix configuration parameters

# ------------------------------------------------------------------------------
# Postgres database parameters
# ------------------------------------------------------------------------------
#  ONEAPP_ZABBIX_DB_USER: User for the Zabbix database
#
#  ONEAPP_ZABBIX_DB_PASSWORD: Password for Zabbix database user
#
#  ONEAPP_ZABBIX_DB_NAME: Name for the Zabbix database
# ------------------------------------------------------------------------------
ONEAPP_ZABBIX_DB_USER = env :ONEAPP_ZABBIX_DB_USER, 'zabbix'
ONEAPP_ZABBIX_DB_PASSWORD = env :ONEAPP_ZABBIX_DB_PASSWORD, ''
ONEAPP_ZABBIX_DB_NAME = env :ONEAPP_ZABBIX_DB_NAME, 'zabbix'

# ------------------------------------------------------------------------------
# Zabbix configuration parameters
# ------------------------------------------------------------------------------
#  ONEAPP_ZABBIX_PORT: Listen port for Nginx configuration
#
#  ONEAPP_ZABBIX_SERVER_NAME: Server name for Nginx configuration
# ------------------------------------------------------------------------------
ONEAPP_ZABBIX_PORT = env :ONEAPP_ZABBIX_PORT, '8080'
ONEAPP_ZABBIX_SERVER_NAME = env :ONEAPP_ZABBIX_SERVER_NAME, 'example.com'
