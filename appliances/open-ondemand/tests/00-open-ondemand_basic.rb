require_relative '../../../lib/community/app_handler'

# Certification tests for the Open OnDemand appliance.
#
# The harness starts one VM on its own, with no NFS server, no LDAP directory and no
# CernVM-FS proxy, because those belong to the other roles of the OneFlow service. So these
# tests check what a single VM can honestly prove: that the image carries the software of
# all three roles, that the role switch is present and refuses an unknown role, and that no
# role service is left running in an image meant to become any of the three.
#
# What a single VM cannot prove is left to the service: the shared home, the identity
# directory, the software catalogue and the elastic pool. Those are covered by the
# acceptance suite of the project, which drives a full deployment.
describe 'Appliance Certification' do
    include_context('vm_handler')

    it 'carries the worker software: Apptainer, the session image and code-server' do
        @info[:vm].ssh('command -v apptainer').expect_success
        @info[:vm].ssh('test -s /opt/ood/linuxhost.sif').expect_success
        @info[:vm].ssh('test -s /etc/open-ondemand/code-server.env').expect_success
    end

    it 'carries the CernVM-FS client that serves the EESSI catalogue' do
        @info[:vm].ssh('command -v cvmfs_config').expect_success
        @info[:vm].ssh('dpkg -s cvmfs-config-eessi').expect_success
    end

    it 'carries the storage software: NFS server and the site cache' do
        @info[:vm].ssh('command -v exportfs').expect_success
        @info[:vm].ssh('command -v squid').expect_success
    end

    it 'carries the portal software: Open OnDemand, its Dex and the directory' do
        @info[:vm].ssh('dpkg -s ondemand').expect_success
        @info[:vm].ssh('dpkg -s ondemand-dex').expect_success
        @info[:vm].ssh('test -x /opt/ood/ood-portal-generator/sbin/update_ood_portal').expect_success
        @info[:vm].ssh('command -v slapadd').expect_success
    end

    it 'carries the Slurm cluster software for the portal and the workers' do
        %w[slurmctld slurmdbd slurmd slurm-client munge mariadb-server].each do |pkg|
            @info[:vm].ssh("dpkg -s #{pkg}").expect_success
        end
        @info[:vm].ssh('test -x /opt/open-ondemand/scripts/40-configure-slurm-controller.sh').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/worker/slurm-task-prolog.sh').expect_success
        @info[:vm].ssh('test -x /usr/local/bin/ood-slurm-elastic.sh').expect_success
        # The key of a service is generated at boot and must never travel inside the image.
        @info[:vm].ssh('test -e /etc/munge/munge.key').expect_fail
        @info[:vm].ssh('id slurm && id munge').expect_success
    end

    it 'has the role switch and its own copy of the appliance code' do
        @info[:vm].ssh('test -x /usr/local/sbin/ood-appliance-configure').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/worker/configure.sh').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/storage/10-install-nfs.sh').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/scripts/30-configure-portal.sh').expect_success
    end

    it 'carries the shared software directory pieces: the eessi user, the operator command and a recipe' do
        @info[:vm].ssh('id -u eessi').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/scripts/ood-site-install.sh').expect_success
        @info[:vm].ssh('test -x /opt/open-ondemand/scripts/75-mount-software.sh').expect_success
        @info[:vm].ssh('test -f /opt/open-ondemand/config/easybuild/hello-2.12.1-GCCcore-14.3.0.eb').expect_success
    end

    it 'refuses a role it does not implement' do
        # A typo in ONEAPP_ROLE has to fail loudly. Silently doing nothing would leave a VM
        # that looks deployed and serves nothing, which is the worst outcome of the three.
        cmd = 'ONEAPP_ROLE=nosuchrole /usr/local/sbin/ood-appliance-configure'
        @info[:vm].ssh(cmd).expect_fail
    end

    it 'leaves no role service running in the image' do
        # One image serves three roles, so none of their services may start on its own: a
        # worker running Apache and an empty directory would be attack surface for nothing,
        # and a portal exporting NFS would be a mistake that is hard to see.
        %w[apache2 ondemand-dex slapd nfs-server squid slurmctld slurmdbd slurmd mariadb].each do |unit|
            @info[:vm].ssh("systemctl is-enabled #{unit}").expect_fail
        end
    end

    it 'records what it was built from' do
        out = @info[:vm].ssh('cat /etc/open-ondemand/build.env').stdout
        expect(out).to match(/^APPLIANCE=open-ondemand$/)
        expect(out).to match(/^APPLIANCE_ROLES=portal,storage,worker$/)
        expect(out).to match(/^BUILD_DATE=/)
    end
end
