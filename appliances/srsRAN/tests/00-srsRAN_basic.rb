require_relative '../../../lib/community/app_handler'

describe 'srsRAN Project Appliance' do
  include_context('vm_handler')

  def files_dirs_exist?(paths, type = :file)
    paths.each do |path|
      case type
      when :file
        cmd = "test -f #{path}"
      when :dir
        cmd = "test -d #{path}"
      else
        raise ArgumentError, "Invalid type: #{type}. Must be :file or :dir."
      end

      execution = @info[:vm].ssh(cmd)
      expect(execution.success?).to be(true), "#{path} does not exist or is not a #{type.to_s}"
    end
  end

  it 'should verify srsRAN base installation' do
    files_dirs_exist?(['/usr/local/srsran/bin/gnb', '/usr/local/srsran/bin/srscu', '/usr/local/srsran/bin/srsdu'])
    files_dirs_exist?(['/usr/local/srsran'], :dir)
  end

  it 'should verify srsRAN configuration directories' do
    files_dirs_exist?(['/etc/srsran', '/var/log/srsran', '/opt/srsran'], :dir)
  end

  it 'should verify systemd services are installed' do
    files_dirs_exist?(['/etc/systemd/system/srsran-gnb.service', '/etc/systemd/system/srsran-cu.service', '/etc/systemd/system/srsran-du.service'])
  end

  it 'should verify srsRAN binaries are executable' do
    cmd = "/usr/local/srsran/bin/gnb --version"
    @info[:vm].ssh(cmd).expect_success
  end

  it 'should verify LinuxPTP installation for clock synchronization' do
    ['ptp4l', 'phc2sys'].each do |service|
      cmd = "which #{service}"
      @info[:vm].ssh(cmd).expect_success
    end
  end

  it 'should verify RT kernel is installed' do
    cmd = "uname -r | grep -q rt"
    @info[:vm].ssh(cmd).expect_success
  end
end
