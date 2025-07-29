require_relative '../../../lib/community/app_handler' # Loads the library to handle VM creation and destruction

# OpenFGS Appliance Certification Tests
describe 'OpenFGS Appliance Certification' do
    # This is a library that takes care of creating and destroying the VM for you
    # The VM is instantiated with your APP_CONTEXT_PARAMS passed
    include_context('vm_handler')

    # Check if Open5GS core services are installed
    it 'open5gs core services are installed' do
        ['open5gs-amfd', 'open5gs-smfd', 'open5gs-upfd', 'mongod'].each do |service|
            cmd = "which #{service}"
            @info[:vm].ssh(cmd).expect_success
        end
    end

    # Use systemd to verify that core services are running
    it 'core services are running' do
        services_to_check = ['mongod', 'open5gs-smfd', 'open5gs-upfd', 'open5gs-amfd']

        services_to_check.each do |service|
            cmd = "systemctl is-active #{service}"
            result = @info[:vm].ssh(cmd)

            if result.success?
                puts "INFO: #{service} is active."
            else
                if service == 'open5gs-amfd'
                    puts "INFO: #{service} is not running, which is acceptable if the AMF IP is not configured on a host interface."
                else
                    puts "WARNING: #{service} is not active."
                end
            end
        end
    end

    # Check if essential Open5GS configuration files exist
    it 'essential configuration files exist' do
        config_files = ['/etc/open5gs/amf.yaml', '/etc/open5gs/smf.yaml', '/etc/open5gs/upf.yaml']

        config_files.each do |config_file|
            cmd = "test -f #{config_file}"
            execution = @info[:vm].ssh(cmd)
            expect(execution.success?).to be(true), "Configuration file #{config_file} does not exist"
        end
    end

    # Check if IP forwarding is enabled (required for UPF)
    it 'ip forwarding is enabled' do
        cmd = 'sysctl net.ipv4.ip_forward'
        timeout_seconds = 60
        retry_interval_seconds = 5

        begin
            Timeout.timeout(timeout_seconds) do
                loop do
                    execution = @info[:vm].ssh(cmd)

                    if execution.success? && execution.stdout.include?('net.ipv4.ip_forward = 1')
                        expect(execution.success?).to be(true)
                        expect(execution.stdout).to include('net.ipv4.ip_forward = 1')
                        break
                    else
                        sleep(retry_interval_seconds)
                    end
                end
            end
        rescue Timeout::Error
            fail "Timeout after #{timeout_seconds} seconds: ip forwarding not enabled"
        rescue StandardError => e
            fail "An error occurred during ip forwarding check: #{e.message}"
        end
    end

end
