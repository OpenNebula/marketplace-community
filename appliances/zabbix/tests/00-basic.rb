require_relative '../../../lib/community/app_handler' # Loads the library to handle VM creation and destruction

# You can put any title you want, this will be where you group your tests
describe 'Appliance Certification' do
    # This is a library that takes care of creating and destroying the VM for you
    # The VM is instantiated with your APP_CONTEXT_PARAMS passed
    # "onetemplate instantiate base --context SSH_PUBLIC_KEY=\\\"\\$USER[SSH_PUBLIC_KEY]\\\",NETWORK=\"YES\",ONEAPP_DB_NAME=\"dbname\",ONEAPP_DB_USER=\"username\",ONEAPP_DB_PASSWORD=\"upass\",ONEAPP_DB_ROOT_PASSWORD=\"arpass\" --disk service_example"
    include_context('vm_handler')

    # if the psql command exists in $PATH, we can assume it is installed
    it 'postgresql is installed' do
        cmd = 'which psql'

        # use @info[:vm] to test the VM running the app
        @info[:vm].ssh(cmd).expect_success
    end

    # if the zabbix_server command exists in $PATH, we can assume it is installed
    it 'zabbix_server is installed' do
        cmd = 'which zabbix_server'

        # use @info[:vm] to test the VM running the app
        @info[:vm].ssh(cmd).expect_success
    end

    # Use the systemd cli to verify that postgresql is up and runnig. will fail if it takes more than 30 seconds to run
    it 'postgresql service is running' do
        cmd = 'systemctl is-active postgresql'
        start_time = Time.now
        timeout = 30

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "MySQL service did not become active within #{timeout} seconds"
            end

            sleep 1
        end
    end

    # Use the systemd cli to verify that zabbix-server is up and runnig. will fail if it takes more than 60 seconds to run
    it 'zabbix-server service is running' do
        cmd = 'systemctl is-active postgresql'
        start_time = Time.now
        timeout = 60

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Zabbix-server service did not become active within #{timeout} seconds"
            end

            sleep 1
        end
    end

    # Check if the service framework from one-apps reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'

        execution = @info[:vm].ssh(cmd)

        # you can use pp to help with logging.
        # This doesn't verify anything, but helps with inspections
        # In this case, we display the motd you get when connecting to the app instance via ssh
        pp execution.stdout

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('All set and ready to serve')
    end

    # use mysql CLI to verify that the database has been created
    it 'database exists' do
        db = APP_CONTEXT_PARAMS[:ZABBIX_DB_NAME]

        cmd = "sudo su postgres -c 'psql -l | grep #{db} | wc -l'"

        execution = @info[:vm].ssh(cmd)
        expect(execution.stdout.strip.to_i).to eq(1)
    end
end

# Example run
# rspec -f d tutorial_tests.rb
# Appliance Certification
# "onetemplate instantiate base --context SSH_PUBLIC_KEY=\\\"\\$USER[SSH_PUBLIC_KEY]\\\",NETWORK=\"YES\",ONEAPP_DB_NAME=\"dbname\",ONEAPP_DB_USER=\"username\",ONEAPP_DB_PASSWORD=\"upass\",ONEAPP_DB_ROOT_PASSWORD=\"arpass\" --disk service_example"
#   mysql is installed
#   mysql service is running
# "\n" +
# "    ___   _ __    ___\n" +
# "   / _ \\ | '_ \\  / _ \\   OpenNebula Service Appliance\n" +
# "  | (_) || | | ||  __/\n" +
# "   \\___/ |_| |_| \\___|\n" +
# "\n" +
# " All set and ready to serve 8)\n" +
# "\n"
#   check oneapps motd
#   can connect as root with defined password
#   database exists
#   can connect as user with defined password

# Finished in 1 minute 25.9 seconds (files took 0.22136 seconds to load)
# 6 examples, 0 failures
