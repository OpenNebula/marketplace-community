# Nextcloud AIO on openSUSE Appliance

[Nextcloud All-in-One (AIO)](https://hub.docker.com/r/nextcloud/all-in-one) running on openSUSE Leap 15 with Docker. Includes Nextcloud Office, Talk, automatic updates and backups.

## Quick Start

1. **Export from Marketplace:**
   ```bash
   onemarketapp export 'Nextcloud AIO on openSUSE' nextcloud-suse --datastore default
   ```

2. **Instantiate the template:**
   ```bash
   onetemplate instantiate nextcloud-suse
   ```

3. **Attach network:**
   ```bash
   onevm nic-attach VM_ID --network VNET_ID
   ```

4. **Verify the container:**
   ```bash
   onevm ssh VM_ID
   docker ps
   ```

5. **Access web interface:** Open `https://VM_IP:8080` — the master password is shown on the AIO Welcome Screen.

> **Private network?** Use SSH port forwarding: `ssh -L 8080:VM_IP:8080 user@opennebula-host` then open `https://localhost:8080`

## Default Configuration

| Parameter | Default Value |
|-----------|---------------|
| Container Name | `nextcloud-suse-container` |
| Ports | `80:80,8080:8080,8443:8443` |
| Environment | `SKIP_DOMAIN_VALIDATION=true` |
| Volumes | `/var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config` |

## Management Commands

```bash
docker ps                                      # View containers
docker logs nextcloud-suse-container           # View logs
docker exec -it nextcloud-suse-container bash  # Access shell
docker restart nextcloud-suse-container        # Restart
```

## Technical Details

| | |
|-|-|
| **Base OS** | openSUSE Leap 15 |
| **Container** | [nextcloud/all-in-one:latest](https://hub.docker.com/r/nextcloud/all-in-one) |
| **Requirements** | 2GB RAM, 8GB disk minimum |

## Resources

- [Nextcloud AIO Docker Hub](https://hub.docker.com/r/nextcloud/all-in-one) — Full documentation and configuration
- [Nextcloud AIO GitHub](https://github.com/nextcloud/all-in-one) — Source code and issues
