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
        ['mongod', 'open5gs-amfd', 'open5gs-smfd', 'open5gs-upfd'].each do |service|
            cmd = "systemctl is-active #{service}"
            start_time = Time.now
            timeout = 60

            loop do
                result = @info[:vm].ssh(cmd)
                break if result.success?

                if Time.now - start_time > timeout
                    raise "#{service} service did not become active within #{timeout} seconds"
                end

                sleep 2
            end
        end
    end

    # Check if the service framework from one-apps reports that the app is ready
    it 'check oneapps motd' do
        cmd = 'cat /etc/motd'

        execution = @info[:vm].ssh(cmd)

        # Display the motd for inspection
        pp execution.stdout

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('All set and ready to serve')
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

        execution = @info[:vm].ssh(cmd)
        expect(execution.success?).to be(true)
        expect(execution.stdout).to include('net.ipv4.ip_forward = 1')
    end

end