# Basic test for Prowler appliance

require_relative '../../../lib/tests'

class TestProwlercloud < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_image_pulled
    assert_cmd("docker images | grep 'prowlercloud/prowler:latest-amd64'")
  end

  def test_container_running
    assert_cmd("docker ps | grep 'prowler'")
  end
end
