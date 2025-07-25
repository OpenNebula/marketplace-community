#!/usr/bin/env ruby

require_relative '../../../lib/community/app_handler'

app_handler = AppHandler.new

RSpec.describe 'srsRAN Project Appliance' do
  before(:all) do
    app_handler.create_vm
  end

  after(:all) do
    app_handler.destroy_vm
  end

  it 'should verify srsRAN base installation' do
    expect(app_handler.ssh_exec('test -d /usr/local/srsran')).to be_truthy
    expect(app_handler.ssh_exec('test -f /usr/local/srsran/bin/gnb')).to be_truthy
    expect(app_handler.ssh_exec('test -f /usr/local/srsran/bin/srscu')).to be_truthy
    expect(app_handler.ssh_exec('test -f /usr/local/srsran/bin/srsdu')).to be_truthy
  end

  it 'should verify srsRAN configuration directories' do
    expect(app_handler.ssh_exec('test -d /etc/srsran')).to be_truthy
    expect(app_handler.ssh_exec('test -d /var/log/srsran')).to be_truthy
    expect(app_handler.ssh_exec('test -d /opt/srsran')).to be_truthy
  end

  it 'should verify systemd services are installed' do
    expect(app_handler.ssh_exec('test -f /etc/systemd/system/srsran-gnb.service')).to be_truthy
    expect(app_handler.ssh_exec('test -f /etc/systemd/system/srsran-cu.service')).to be_truthy
    expect(app_handler.ssh_exec('test -f /etc/systemd/system/srsran-du.service')).to be_truthy
  end

  it 'should verify oneapps motd' do
    expect(app_handler.ssh_exec('grep -q "oneapps" /etc/motd')).to be_truthy
  end

  it 'should verify srsRAN binaries are executable' do
    expect(app_handler.ssh_exec('/usr/local/srsran/bin/gnb --version')).to be_truthy
  end

  it 'should verify LinuxPTP installation for clock synchronization' do
    expect(app_handler.ssh_exec('which ptp4l')).to be_truthy
    expect(app_handler.ssh_exec('which phc2sys')).to be_truthy
  end

  it 'should verify RT kernel is installed' do
    expect(app_handler.ssh_exec('uname -r | grep -q rt')).to be_truthy
  end
end