require_relative '../../../lib/community/app_handler'

# Nginx Docker Appliance Certification Tests
describe 'Appliance Certification' do
    include_context('vm_handler')

    it 'docker is installed' do
        cmd = 'which docker'
        @info[:vm].ssh(cmd).expect_success
    end

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

    it 'nginx container is running' do
        cmd = 'docker ps --filter "name=nginx-container" --format "{{.Names}}"'
        start_time = Time.now
        timeout = 120

        execution = nil
        loop do
            execution = @info[:vm].ssh(cmd)
            break if execution.success? && execution.stdout.include?('nginx-container')

            if Time.now - start_time > timeout
                raise "Nginx container not found within #{timeout} seconds"
            end

            sleep 5
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('nginx-container')
    end

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
        end
    end
end
