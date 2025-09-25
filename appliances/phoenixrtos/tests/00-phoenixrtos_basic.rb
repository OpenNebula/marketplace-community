require_relative '../../../lib/community/app_handler'

# Phoenix RTOS Docker Appliance Certification Tests
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

    it 'phoenix-rtos-one container is running' do
        cmd = 'docker ps --filter "name=phoenix-rtos-one" --format "{{.Names}}"'
        start_time = Time.now
        timeout = 180  # Phoenix RTOS container may take longer to start

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

    it 'phoenix-rtos container is responsive' do
        cmd = 'docker exec phoenix-rtos-one echo "Phoenix RTOS is running"'
        start_time = Time.now
        timeout = 60

        execution = nil
        loop do
            execution = @info[:vm].ssh(cmd)
            break if execution.success? && execution.stdout.include?('Phoenix RTOS is running')

            if Time.now - start_time > timeout
                raise "Phoenix RTOS container not responsive within #{timeout} seconds"
            end

            sleep 3
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('Phoenix RTOS is running')
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

    it 'vnc service is available' do
        cmd = 'ss -tlnp | grep :5900'
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include(':5900')
    end
end
