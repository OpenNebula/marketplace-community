require_relative '../../../lib/community/app_handler'

# Basic tests for Prowler Security Platform appliance
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

    # Check if Docker Compose is installed
    it 'docker compose is installed' do
        cmd = 'docker compose version'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if Prowler data directory exists
    it 'prowler data directory exists' do
        cmd = 'test -d /opt/prowler'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if docker-compose.yml is configured
    it 'docker-compose.yml is configured' do
        cmd = 'test -f /opt/prowler/docker-compose.yml'
        start_time = Time.now
        timeout = 120

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "docker-compose.yml not found within #{timeout} seconds"
            end

            sleep 5
        end
    end

    # Check if .env file is configured
    it 'environment file is configured' do
        cmd = 'test -f /opt/prowler/.env'
        result = @info[:vm].ssh(cmd)
        expect(result.exitstatus).to eq(0)
    end

    # Check if all Prowler containers are running
    it 'prowler containers are running' do
        # Check for all required services: api, ui, postgres, valkey, neo4j, mcp-server
        cmd = "docker ps | grep -E 'prowler.*api|prowler.*ui|prowler.*mcp|postgres|valkey|neo4j|dozerdb'"
        start_time = Time.now
        timeout = 420  # 7 minutes - containers take time to initialize, especially Neo4j

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Prowler containers did not start within #{timeout} seconds"
            end

            sleep 10
        end
    end

    # Check if Neo4j is healthy
    it 'neo4j is healthy' do
        cmd = 'docker ps --filter "name=neo4j" --format "{{.Status}}" | grep -i healthy'
        start_time = Time.now
        timeout = 300

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            if Time.now - start_time > timeout
                raise "Neo4j did not become healthy within #{timeout} seconds"
            end

            sleep 10
        end
    end

    # Check if MCP server is healthy
    it 'mcp server is healthy' do
        cmd = 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health'
        start_time = Time.now
        timeout = 180

        loop do
            result = @info[:vm].ssh(cmd)
            if result.success? && result.stdout.strip == '200'
                break
            end

            if Time.now - start_time > timeout
                raise "MCP server did not respond within #{timeout} seconds"
            end

            sleep 10
        end
    end

    # Check if API is responding
    it 'prowler API is responding' do
        cmd = 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/v1/docs'
        start_time = Time.now
        timeout = 300

        loop do
            result = @info[:vm].ssh(cmd)
            if result.success? && ['200', '301', '302'].include?(result.stdout.strip)
                break
            end

            if Time.now - start_time > timeout
                raise "Prowler API did not respond within #{timeout} seconds"
            end

            sleep 10
        end
    end

    # Check if UI is responding
    it 'prowler UI is responding' do
        cmd = 'curl -s -o /dev/null -w "%{http_code}" http://localhost:3000'
        start_time = Time.now
        timeout = 300

        loop do
            result = @info[:vm].ssh(cmd)
            if result.success? && ['200', '301', '302'].include?(result.stdout.strip)
                break
            end

            if Time.now - start_time > timeout
                raise "Prowler UI did not respond within #{timeout} seconds"
            end

            sleep 10
        end
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

    # Check if helper commands exist
    it 'helper commands exist' do
        %w[prowler-status prowler-logs prowler-restart].each do |cmd|
            result = @info[:vm].ssh("which #{cmd}")
            expect(result.exitstatus).to eq(0)
        end
    end
end
