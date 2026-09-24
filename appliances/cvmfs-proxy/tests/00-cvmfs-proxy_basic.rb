require 'base64'
require_relative '../../../lib/community/app_handler'

# Certification tests for the CernVM-FS Proxy appliance.
#
# The harness starts one VM with the context of metadata.yaml. The tests check that Squid
# runs with the configuration that the context asks for, that a client on the subnet of the
# VM gets a CernVM-FS file through the proxy, and that a destination outside the list is
# refused. The requests go to the address of the VM and not to localhost, because localhost
# is always allowed and would prove nothing about the client rule.
#
# The harness wraps every command in double quotes on the front-end, so a command with a $
# or a quote would be expanded there. on_vm sends the script in base64 and the VM runs it
# exactly as written.
describe 'Appliance Certification' do
    include_context('vm_handler')

    PROXY_CHECK_URL = 'http://aws-eu-central-s1.eessi.science/cvmfs/software.eessi.io/.cvmfspublished'
    PROXY_OF_VM = 'http://$(hostname -I | cut -d" " -f1):3128'

    def on_vm(script)
        @info[:vm].ssh("echo #{Base64.strict_encode64(script)} | base64 -d | bash")
    end

    it 'squid is active' do
        start = Time.now
        timeout = 300
        loop do
            r = @info[:vm].ssh('systemctl is-active squid')
            break if r.stdout.strip == 'active'
            raise "squid is not active after #{timeout} seconds" if Time.now - start > timeout

            sleep 10
        end
    end

    it 'the appliance reports that it is ready' do
        start = Time.now
        timeout = 300
        loop do
            r = @info[:vm].ssh('cat /etc/motd')
            break if r.stdout.include?('All set and ready to serve')
            raise "the appliance is not ready after #{timeout} seconds" if Time.now - start > timeout

            sleep 10
        end
    end

    it 'squid accepts its configuration and listens on port 3128' do
        @info[:vm].ssh('squid -k parse').expect_success
        r = on_vm('ss -ltnH "( sport = :3128 )"')
        expect(r.stdout.strip).not_to be_empty
    end

    it 'squid.conf has the CernVM-FS settings and the sizes from the context' do
        disk = APP_CONTEXT_PARAMS[:ONEAPP_CACHE_SIZE_DISK]
        mem = APP_CONTEXT_PARAMS[:ONEAPP_CACHE_SIZE_MEMORY]
        conf = @info[:vm].ssh('cat /etc/squid/squid.conf').stdout
        ['collapsed_forwarding on',
         'minimum_expiry_time 0',
         'maximum_object_size 1024 MB',
         'maximum_object_size_in_memory 128 KB',
         "cache_mem #{mem} MB",
         "cache_dir ufs /var/spool/squid #{disk} 16 256",
         'acl stratum_ones dstdomain -n .cern.ch .gridpp.rl.ac.uk .opensciencegrid.org .eessi.science',
         'http_access deny !stratum_ones'].each do |line|
            expect(conf.lines.map(&:strip)).to include(line)
        end
    end

    it 'allows the subnet of the first NIC by default' do
        cmd = <<~'CMD'
            python3 -c '
            import ipaddress, re, subprocess
            conf = open("/etc/squid/squid.conf").read()
            nets = [ipaddress.ip_network(n) for n in re.findall(r"^acl local_nodes src (\S+)$", conf, re.M)]
            ip = ipaddress.ip_address(subprocess.check_output(["hostname", "-I"]).split()[0].decode())
            assert any(ip in n for n in nets), (ip, nets)
            '
        CMD
        on_vm(cmd).expect_success
    end

    it 'serves a CernVM-FS file of EESSI to a client of its subnet' do
        r = on_vm("curl -s --head --max-time 30 -x #{PROXY_OF_VM} #{PROXY_CHECK_URL} | head -1")
        expect(r.stdout.strip).to match(%r{^HTTP/1\.1 200})
    end

    it 'refuses a destination that is not in the list' do
        cmd = "curl -s -o /dev/null -w '%{http_code}' --max-time 30 -x #{PROXY_OF_VM} http://example.com/"
        r = on_vm(cmd)
        expect(r.stdout.strip).to eq('403')
    end

    it 'refuses an address whose reverse DNS name is in the list' do
        # The address of a CERN server has a PTR under cern.ch. Squid must not trust it, or any
        # server with such a PTR would be reachable through the proxy.
        cmd = <<~'CMD'
            ip=$(getent ahostsv4 cvmfs-stratum-one.cern.ch | awk '{print $1; exit}')
            curl -s -o /dev/null -w '%{http_code}' --max-time 30 -x http://$(hostname -I | cut -d" " -f1):3128 http://$ip/cvmfs/cvmfs-config.cern.ch/.cvmfspublished
        CMD
        r = on_vm(cmd)
        expect(r.stdout.strip).to eq('403')
    end

    it 'records both requests in the access log' do
        log = @info[:vm].ssh('cat /var/log/squid/access.log').stdout
        expect(log).to match(/TCP_\S+ .*aws-eu-central-s1\.eessi\.science/)
        expect(log).to match(%r{TCP_DENIED/403 .*example\.com})
    end

    it 'writes the URL of the proxy for the operator' do
        r = on_vm('grep "^url" /etc/one-appliance/config')
        expect(r.stdout).to match(%r{url\s+= http://\d+\.\d+\.\d+\.\d+:3128})
    end
end
