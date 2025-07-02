require_relative '../../../lib/community/app_handler' # Loads the library to handle VM creation and destruction

# You can put any title you want, this will be where you group your tests
describe 'Appliance Certification' do
    # This is a library that takes care of creating and destroying the VM for you
    # The VM is instantiated with your APP_CONTEXT_PARAMS passed
    include_context('vm_handler')

    # if the rabbitmq-server command exists in $PATH, we can assume it is installed
    it 'rabbitmq-server is installed' do
        cmd = 'which rabbitmq-server'

        # use @info[:vm] to test the VM running the app
        @info[:vm].ssh(cmd).expect_success
    end

    # Use the systemd cli to verify that rabbitmq-server is up and runnig. will fail if it takes more than 30 seconds to run
    it 'rabbitmq-server service is running' do
        cmd = 'systemctl is-active rabbitmq-server'
        start_time = Time.now
        timeout = 30

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "RabbitMQ service did not become active within #{timeout} seconds"
            end

            sleep 1
        end
    end

    # Check if the service framework from one-apps reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'

        max_retries = 5
        sleep_time = 5
        expected_motd = 'All set and ready to serve'
      
        execution = nil
        max_retries.times do |attempt|
          execution = @info[:vm].ssh(cmd)
          #pp execution.stdout  # Debugging output
      
          if execution.stdout.include?(expected_motd)
            break  # Exit loop early if MOTD is correct
          end
      
          puts "Attempt #{attempt + 1}/#{max_retries}: Waiting for MOTD to update..."
          sleep sleep_time
        end
      
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include(expected_motd)
    end

    # use CLI to verify user authentication
    it 'validate rabbitmq credentials' do
        user = APP_CONTEXT_PARAMS[:ONEAPP_RABBITMQ_USER]
        cmd = "rabbitmqctl list_users"
        execution = @info[:vm].ssh(cmd)
        #pp execution.stdout  # Debugging output
        expect(execution.stdout).to include(user)
    end

end
