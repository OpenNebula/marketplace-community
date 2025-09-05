# Lithops OneFlow Service

The Lithops OneFlow Service provides a way of deploying a Lithops environment using Lithops Worker compute backend and MinIO as a storage bakend. This template will deploy a Lithops Client role that has a preinstalled [Lithops](https://github.com/OpenNebula/lithops), currently using branch f-569, with a storage role based on [MinIO appliance](https://github.com/OpenNebula/one-apps/wiki/minio_intro), a [RabbitMQ appliance](https://github.com/OpenNebula/marketplace-community/wiki/rabbitmq_intro) as message broker and a Lithops Worker appliances as compute backends.

The following roles are defined:

* **Lithops - Client**: Ubuntu based VM template with a preconfigured working Lithops installation, that will be configured to use the Lithops Worker as compute backend, RabbitMQ as message broker and the MinIO server as storage backend.
* **Lithops - Worker**: Role for the Lithops backend computing.
* **Lithops - Virtual Router**: Virtual Router that will configure access between the different components. Based on Service Virtual Router.
* **Lithops - MinIO**: MinIO storage backend. It can be configured as Single-Node or Multi-Node following MinIO appliance's documentation.
* **RabbitMQ**: RabbitMQ AMQP message broker. Used to distribute Lithops Client messages to backend nodes.


## Downloading and Deploying Lithops Service

1. Download the `Lithops Service` appliance from the OpenNebula Community Marketplace:

   ```shell
   $ onemarketapp export 'Lithops Service' 'Lithops Service' --datastore default
   ```
2. Adjust Lithops Service Template to your needs. Add the necessary additional drives to the MinIO template as documented in the [MinIO -Quick Start](https://github.com/OpenNebula/one-apps/wiki/minio_quick) guide. You can also set the CPU and RAM for the VMs in each role.
3. Configure networks for the Lithops Service Template, by selecting the OpenNebula existing private and public networks that the service will use. 
4. Configure role MinIO parameters to match your needs, following MinIO appliance documentation for Single-Node or Multi-Node deployments.
5. Instantiate the Flow service:
   
   ```shell
   $ oneflow-template instantiate 'Lithops Service Template' /tmp/LithopsService-instantiate
   ```
6. Access the Lithops role instance connecting through the public NIC of the vr role VM.
   ```shell
   $ ssh -A -J root@vr-public-ip root@lithops-private-ip
   ```

## Requirements

* OpenNebula version: >= 6.8
* [OneFlow](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/overview.html) and [OneGate](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/onegate_usage.html) for multi-node orchestration.
