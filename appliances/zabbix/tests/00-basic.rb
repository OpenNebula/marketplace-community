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
    it 'checks oneapps motd' do
        cmd = 'cat /etc/motd'
        timeout_seconds = 60
        retry_interval_seconds = 5

        begin
            Timeout.timeout(timeout_seconds) do
                loop do
                    execution = @info[:vm].ssh(cmd)

                    if execution.exitstatus == 0 && execution.stdout.include?('All set and ready to serve')
                        expect(execution.exitstatus).to eq(0) # Assert exit status
                        expect(execution.stdout).to include('All set and ready to serve')
                        break
                    else
                        sleep(retry_interval_seconds)
                    end
                end
            end
        rescue Timeout::Error
            fail "Timeout after #{timeout_seconds} seconds: MOTD did not contain 'All set and ready to serve'. Appliance not configured."
        rescue StandardError => e
            fail "An error occurred during MOTD check: #{e.message}"
        end
    end

    # use mysql CLI to verify that the database has been created
    it 'database exists' do
        db = APP_CONTEXT_PARAMS[:ZABBIX_DB_NAME]

        cmd = "sudo su postgres -c 'psql -l | grep #{db} | wc -l'"

        execution = @info[:vm].ssh(cmd)
        expect(execution.stdout.strip.to_i).to eq(1)
    end
end
