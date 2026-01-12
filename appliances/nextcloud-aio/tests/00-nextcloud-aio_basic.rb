require_relative '../../../lib/community/app_handler' # Loads the library to handle VM creation and destruction

# Basic tests for Nextcloud AIO on openSUSE appliance
describe 'Appliance Certification' do
    # This is a library that takes care of creating and destroying the VM for you
    include_context('vm_handler')

    # Check if Docker is installed
    it 'docker is installed' do
        cmd = 'which docker'
        start_time = Time.now
        timeout = 120  # Wait up to 2 minutes for SSH to become available

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Docker not found or SSH not available within #{timeout} seconds"
            end

            sleep 5
        end
    end

    # Use the systemd cli to verify that docker is up and running
    it 'docker service is running' do
        cmd = 'systemctl is-active docker'
        start_time = Time.now
        timeout = 30

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Docker service did not become active within #{timeout} seconds"
            end

            sleep 1
        end
    end

    # Check if the Nextcloud AIO image is pulled
    it 'nextcloud aio image is present' do
        cmd = "docker images | grep 'nextcloud/all-in-one'"
        start_time = Time.now
        timeout = 60

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Nextcloud AIO image not found within #{timeout} seconds"
            end

            sleep 5
        end
    end

    # Check if the Nextcloud AIO container is running
    it 'nextcloud aio container is running' do
        # The container name is nextcloud-aio-mastercontainer (required by Nextcloud AIO)
        cmd = "docker ps | grep -E 'nextcloud-aio-mastercontainer|nextcloud-aio'"
        start_time = Time.now
        timeout = 300  # 5 minutes - Nextcloud AIO takes time to initialize

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Nextcloud AIO container did not start within #{timeout} seconds"
            end

            sleep 10
        end
    end

    # Check if the service framework from one-apps reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'

        max_retries = 10
        sleep_time = 10
        expected_motd = 'All set and ready to serve'

        execution = nil
        max_retries.times do |attempt|
            execution = @info[:vm].ssh(cmd)

            if execution.stdout.include?(expected_motd)
                break  # Exit loop early if MOTD is correct
            end

            puts "Attempt #{attempt + 1}/#{max_retries}: Waiting for MOTD to update..."
            sleep sleep_time
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include(expected_motd)
    end
end
