require_relative '../../../lib/community/app_handler'

# Basic tests for NemoClaw AI Agent Security appliance
describe 'Appliance Certification' do
    include_context('vm_handler')

    # Check if Docker is installed
    it 'docker is installed' do
        cmd = 'which docker'
        start_time = Time.now
        timeout = 120

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Docker not found or SSH not available within #{timeout} seconds"
            end

            sleep 5
        end
    end

    # Verify that docker service is up and running
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

    # Check if NVIDIA driver is installed
    it 'nvidia driver is installed' do
        cmd = 'dpkg -l | grep nvidia-driver-550-server'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if NVIDIA Container Toolkit is installed
    it 'nvidia container toolkit is installed' do
        cmd = 'which nvidia-ctk'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if Node.js is installed
    it 'nodejs is installed' do
        cmd = 'node --version'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
        expect(result.stdout).to match(/^v22\./)
    end

    # Check if NemoClaw CLI is installed
    it 'nemoclaw cli is installed' do
        cmd = 'which nemoclaw'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if NemoClaw CLI responds
    it 'nemoclaw cli responds' do
        cmd = 'nemoclaw --version'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if swap is configured
    it 'swap is configured' do
        cmd = 'swapon --show | grep -q /swapfile'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if welcome banner exists
    it 'welcome banner exists' do
        cmd = 'test -f /etc/profile.d/99-nemoclaw-welcome.sh'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if the service framework reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'

        max_retries = 30
        sleep_time = 10
        expected_motd = 'All set and ready to serve'

        execution = nil
        max_retries.times do |attempt|
            execution = @info[:vm].ssh(cmd)

            if execution.stdout.include?(expected_motd)
                break
            end

            puts "Attempt #{attempt + 1}/#{max_retries}: Waiting for MOTD to update..."
            sleep sleep_time
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include(expected_motd)
    end
end
