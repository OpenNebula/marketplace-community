require_relative '../../../lib/community/app_handler' # Loads the library to handle VM creation and destruction

# Phoenix RTOS Docker Appliance Certification Tests
describe 'Appliance Certification' do
    # This is a library that takes care of creating and destroying the VM for you
    # The VM is instantiated with your APP_CONTEXT_PARAMS passed
    include_context('vm_handler')

    # Test if Docker is installed and available in PATH
    it 'docker is installed' do
        cmd = 'which docker'
        
        # use @info[:vm] to test the VM running the app
        @info[:vm].ssh(cmd).expect_success
    end

    # Test if Docker Compose is available
    it 'docker compose is available' do
        cmd = 'docker compose version'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Docker Compose')
    end

    # Use systemd CLI to verify that Docker daemon is running
    it 'docker service is running' do
        cmd = 'systemctl is-active docker'
        start_time = Time.now
        timeout = 60

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Docker service did not become active within #{timeout} seconds"
            end

            sleep 2
        end
    end

    # Test Docker functionality by running hello-world container
    it 'docker can run containers' do
        cmd = 'docker run --rm hello-world'
        start_time = Time.now
        timeout = 120

        execution = nil
        loop do
            execution = @info[:vm].ssh(cmd)
            break if execution.success?

            if Time.now - start_time > timeout
                raise "Docker hello-world test failed within #{timeout} seconds"
            end

            sleep 5
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Hello from Docker!')
    end

    # Check if Docker daemon configuration is properly set
    it 'docker daemon configuration is applied' do
        cmd = 'test -f /etc/docker/daemon.json'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
    end

    # Verify Docker version is as expected
    it 'docker version is correct' do
        cmd = 'docker --version'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Docker version')
        # Check for the specific version we install
        expect(execution.stdout).to include('26.1.3')
    end

    # Test Docker Buildx plugin availability if enabled
    it 'docker buildx is available' do
        cmd = 'docker buildx version'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('buildx')
    end

    # Check if the service framework from one-apps reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'
        timeout_seconds = 120
        retry_interval_seconds = 10

        begin
            Timeout.timeout(timeout_seconds) do
                loop do
                    execution = @info[:vm].ssh(cmd)

                    if execution.exitstatus == 0 && execution.stdout.include?('All set and ready to serve')
                        expect(execution.exitstatus).to eq(0)
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

    # Test Docker info command for additional verification
    it 'docker info shows correct configuration' do
        cmd = 'docker info'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Storage Driver: overlay2')
        expect(execution.stdout).to include('Logging Driver: json-file')
    end

    # Test that Docker service is enabled for automatic startup
    it 'docker service is enabled' do
        cmd = 'systemctl is-enabled docker'
        
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout.strip).to eq('enabled')
    end

    # Test basic Docker image operations
    it 'docker can pull and list images' do
        # Pull a small test image
        pull_cmd = 'docker pull alpine:latest'
        execution = @info[:vm].ssh(pull_cmd)
        expect(execution.exitstatus).to eq(0)

        # List images to verify it was pulled
        list_cmd = 'docker images alpine'
        execution = @info[:vm].ssh(list_cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('alpine')
        expect(execution.stdout).to include('latest')
    end

    # Test Docker system information
    it 'docker system shows healthy status' do
        cmd = 'docker system df'

        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('TYPE')
        expect(execution.stdout).to include('TOTAL')
    end

    # Test Phoenix RTOS container is running
    it 'phoenix-rtos container is running' do
        cmd = 'docker ps --filter "name=phoenix-rtos-one" --format "{{.Names}}"'
        start_time = Time.now
        timeout = 120

        execution = nil
        loop do
            execution = @info[:vm].ssh(cmd)
            break if execution.success? && execution.stdout.include?('phoenix-rtos-one')

            if Time.now - start_time > timeout
                raise "Phoenix RTOS container not found within #{timeout} seconds"
            end

            sleep 5
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('phoenix-rtos-one')
    end

    # Test Phoenix RTOS container status
    it 'phoenix-rtos container is healthy' do
        cmd = 'docker ps --filter "name=phoenix-rtos-one" --format "{{.Status}}"'

        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Up')
    end

    # Test Phoenix RTOS image is correct
    it 'phoenix-rtos container uses correct image' do
        cmd = 'docker ps --filter "name=phoenix-rtos-one" --format "{{.Image}}"'

        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('pablodelarco/phoenix-rtos-one')
    end

    # Test Phoenix RTOS container logs
    it 'phoenix-rtos container has logs' do
        cmd = 'docker logs phoenix-rtos-one'

        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        # Phoenix RTOS should produce some output
        expect(execution.stdout.length).to be > 0
    end

    # Test port mapping if configured
    it 'phoenix-rtos container has port mappings' do
        cmd = 'docker ps --filter "name=phoenix-rtos-one" --format "{{.Ports}}"'

        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        # Should have some port mapping (default 8080:8080)
        expect(execution.stdout).to include('8080')
    end
end
