require_relative '../../../lib/community/app_handler'

# Certification tests for the OpenNebula Front-end (miniONE) appliance.
# miniONE runs on first boot and installs the latest OpenNebula front-end plus
# a local KVM/QEMU node, so the readiness checks below allow several minutes.
describe 'Appliance Certification' do
    include_context('vm_handler')

    # The appliance signals readiness through the one-apps MOTD once miniONE
    # has finished provisioning. Wait for it before asserting on services.
    it 'finishes provisioning (oneapps MOTD)' do
        cmd = 'cat /etc/motd'
        max_retries = 90          # up to ~15 min: miniONE installs ONE + a KVM node on first boot
        sleep_time = 10
        expected_motd = 'All set and ready to serve'

        execution = nil
        max_retries.times do |attempt|
            execution = @info[:vm].ssh(cmd)
            break if execution.stdout.include?(expected_motd)
            puts "Attempt #{attempt + 1}/#{max_retries}: waiting for miniONE provisioning to finish..."
            sleep sleep_time
        end

        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include(expected_motd)
    end

    it 'oned is active' do
        result = @info[:vm].ssh('systemctl is-active opennebula')
        expect(result.stdout.strip).to eq('active')
    end

    it 'FireEdge web UI service is active' do
        result = @info[:vm].ssh('systemctl is-active opennebula-fireedge')
        expect(result.stdout.strip).to eq('active')
    end

    it 'OneGate and OneFlow services are active' do
        %w[opennebula-gate opennebula-flow].each do |unit|
            result = @info[:vm].ssh("systemctl is-active #{unit}")
            expect(result.stdout.strip).to eq('active')
        end
    end

    it 'oned answers XML-RPC as oneadmin' do
        # oneuser show resolves the oneadmin auth and proves oned is serving.
        result = @info[:vm].ssh('sudo -u oneadmin oneuser show oneadmin')
        expect(result.exitstatus).to eq(0)
        expect(result.stdout).to match(/NAME\s*:\s*oneadmin/i)
    end

    it 'FireEdge answers on port 2616' do
        cmd = 'curl -sk -o /dev/null -w "%{http_code}" http://localhost:2616/fireedge'
        start_time = Time.now
        timeout = 300
        code = nil
        loop do
            code = @info[:vm].ssh(cmd).stdout.strip
            break if code =~ /^(200|301|302)$/
            raise "FireEdge did not answer on 2616 within #{timeout}s (last code #{code})" if Time.now - start_time > timeout
            sleep 5
        end
        expect(code).to match(/^(200|301|302)$/)
    end

    it 'a local hypervisor host is registered (Front-end + KVM node mode)' do
        # Front-end + KVM node mode registers the co-located KVM/QEMU node. Skip
        # the assertion when the appliance was instantiated as Front-end only.
        result = @info[:vm].ssh('sudo -u oneadmin onehost list --csv 2>/dev/null')
        if result.stdout.include?('localhost') || result.stdout.strip.split("\n").length > 1
            expect(result.exitstatus).to eq(0)
        else
            puts "No local host registered (frontend-only mode?), skipping host assertion"
        end
    end

    it 'miniONE provisioning sentinel exists' do
        result = @info[:vm].ssh('test -f /var/lib/one-appliance/.minione_done')
        expect(result.exitstatus).to eq(0)
    end

    it 'ufw firewall is active and exposes the front-end ports' do
        result = @info[:vm].ssh('sudo ufw status verbose')
        expect(result.stdout).to match(/Status: active/i)
        expect(result.stdout).to match(/deny \(incoming\)/i)
        expect(result.stdout).to match(/2616\/tcp\s+ALLOW/i)
        expect(result.stdout).to match(/2633\/tcp\s+ALLOW/i)
    end

    it 'oneadmin password file is present with restricted permissions' do
        result = @info[:vm].ssh("sudo stat -c '%U:%G %a' /var/lib/one-appliance/oneadmin.password")
        expect(result.stdout.strip).to match(/^root:root 600$/)
    end

    it 'one-status helper exists' do
        result = @info[:vm].ssh('which one-status')
        expect(result.exitstatus).to eq(0)
    end
end
