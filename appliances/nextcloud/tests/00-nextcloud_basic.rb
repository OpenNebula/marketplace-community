# Basic test for nextcloud appliance

require_relative '../../../lib/tests'

class TestNextcloud < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_image_pulled
    assert_cmd("docker images | grep 'nextcloud/all-in-one'")
  end

  def test_container_running
    assert_cmd("docker ps | grep 'nextcloud-aio-mastercontainer'")
  end

  def test_nginx_installed
    assert_cmd('nginx -v')
  end

  def test_nginx_config_exists
    assert_cmd('test -f /etc/nginx/sites-available/nextcloud')
  end

  def test_nginx_ssl_cert_exists
    assert_cmd('test -f /etc/nginx/ssl/nginx.crt')
  end
end
