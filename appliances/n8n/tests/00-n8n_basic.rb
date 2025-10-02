# Basic test for n8n appliance

require_relative '../../../lib/tests'

class TestN8n < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_image_pulled
    assert_cmd("docker images | grep 'n8nio/n8n:latest'")
  end

  def test_container_running
    assert_cmd("docker ps | grep 'n8n-container'")
  end
end
