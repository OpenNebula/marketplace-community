require_relative '../../../lib/community/app_handler'

describe 'Appliance Certification' do
    include_context('vm_handler')

    it 'docker is installed' do
        cmd = 'which docker'
        @info[:vm].ssh(cmd).expect_success
    end

    it 'docker service is running' do
        cmd = 'systemctl is-active docker'
        @info[:vm].ssh(cmd).expect_success
    end

    it 'redis container is running' do
        cmd = 'docker ps --filter "name=redis-container" --format "{{.Names}}"'
        execution = @info[:vm].ssh(cmd)
        expect(execution.exitstatus).to eq(0)
        expect(execution.stdout).to include('redis-container')
    end
end
