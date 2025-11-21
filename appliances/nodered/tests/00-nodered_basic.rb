require_relative '../../../lib/community/app_handler'

describe 'Node-RED Appliance' do
    include_context('vm_handler')

    before(:all) do
        # Wait for contextualization to complete (Docker installation and container startup)
        puts "Waiting for contextualization to complete..."
        sleep 60

        # Wait for Docker service to be ready
        max_wait = 120
        wait_interval = 5
        elapsed = 0

        loop do
            cmd = 'systemctl is-active docker 2>/dev/null'
            result = @info[:vm].ssh(cmd)

            if result.success?
                puts "Docker service is active"
                break
            end

            if elapsed >= max_wait
                puts "Warning: Docker service not active after #{max_wait} seconds"
                break
            end

            puts "Waiting for Docker service... (#{elapsed}s/#{max_wait}s)"
            sleep wait_interval
            elapsed += wait_interval
        end

        # Additional wait for container to start
        sleep 10
    end

    # Test Docker installation
    it 'docker is installed and running' do
        cmd = 'which docker'
        @info[:vm].ssh(cmd).expect_success
        
        cmd = 'systemctl is-active docker'
        @info[:vm].ssh(cmd).expect_success
    end

    # Test Node-RED container image is available
    it 'node-red container image is available' do
        cmd = 'docker images --format "{{.Repository}}:{{.Tag}}" | grep "nodered/node-red:latest"'
        @info[:vm].ssh(cmd).expect_success
    end

    # Test data directory exists
    it 'data directory exists' do
        cmd = 'test -d /data'
        @info[:vm].ssh(cmd).expect_success
    end

    # Test Node-RED container is running
    it 'node-red container is running' do
        cmd = 'docker ps --format "{{.Names}}" | grep "nodered-app"'
        @info[:vm].ssh(cmd).expect_success
    end

    # Test container is responsive
    it 'node-red container is responsive' do
        cmd = 'docker exec nodered-app echo "Container is running"'
        execution = @info[:vm].ssh(cmd)
        expect(execution.success?).to be(true)
        expect(execution.stdout.strip).to eq('Container is running')
    end

    # Test container has correct restart policy
    it 'container has restart policy configured' do
        cmd = 'docker inspect nodered-app --format "{{.HostConfig.RestartPolicy.Name}}"'
        execution = @info[:vm].ssh(cmd)
        expect(execution.success?).to be(true)
        expect(execution.stdout.strip).to eq('unless-stopped')
    end

    # Test container port mapping
    it 'container has port 1880 exposed' do
        cmd = 'docker port nodered-app 1880'
        @info[:vm].ssh(cmd).expect_success
    end

    # Test container volume mapping
    it 'container has data volume mounted' do
        cmd = "docker inspect nodered-app --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' | grep '/data:/data'"
        @info[:vm].ssh(cmd).expect_success
    end

    # Check if the service framework reports ready
    it 'checks oneapps motd' do
        cmd = 'cat /etc/motd'
        timeout_seconds = 60
        retry_interval_seconds = 5

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
            fail "Timeout after #{timeout_seconds} seconds: MOTD did not contain 'All set and ready to serve'"
        end
    end

    # Cleanup: Stop container after tests
    after(:all) do
        if @info && @info[:vm]
            @info[:vm].ssh('docker stop nodered-app || true')
            @info[:vm].ssh('docker rm nodered-app || true')
        end
    end
end

