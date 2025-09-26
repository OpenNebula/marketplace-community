# Basic test for NGINX Web Server appliance

require_relative '../../../lib/tests'

class TestNginx < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_container_service_enabled
    assert_cmd('systemctl is-enabled nginx-container.service')
  end

  def test_image_pulled
    assert_cmd("docker images | grep 'nginx:alpine'")
  end
end
