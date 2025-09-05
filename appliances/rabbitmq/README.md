# Release Notes

Based on Ubuntu 22.04 LTS (for x86-64).

| Component | Version |
| --------- | ------- |
| RabbitMQ  | 4.0.7-1 |

# Features

This appliance comes with RabbitMQ installed globally, following RabbitMQ [official install guide](https://www.rabbitmq.com/docs/install-debian), including the following features:

- Based on the latest RabbitMQ release (4.0.7-1) on Ubuntu 22.04 LTS
- Configuration file in ``/etc/rabbitmq/rabbitmq.conf``
- TLS configuration with self generated certificates.

## Contextualization

The contextualization parameters ([CONTEXT section](https://docs.opennebula.io/stable/management_and_operations)) in the VM template controls the configuration of the service, see the table below

| Parameter                          | Default       | Description                                                                                          |
| ---------------------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| ``ONEAPP_RABBITMQ_NODE_PORT``      | ``5672``      | Port on which the RabbitMQ node will listen for connections                                          |
| ``ONEAPP_RABBITMQ_LOOPBACK_USER``  | ``false``     | Allow the user to connect remotely                                                                   |
| ``ONEAPP_RABBITMQ_USER``   	     | ``rabbitadmin``  | User for RabbitMQ service                                                                         |
| ``ONEAPP_RABBITMQ_PASS``  	     | ``<random>``  | Password for RabbitMQ service                                                                        |
| ``ONEAPP_RABBITMQ_LOG_LEVEL``      |  ``info``     | Controls the granularity of logging  {info,debug}                                                    |
| ``ONEAPP_RABBITMQ_TLS_ENABLED``    |  ``NO``       | Enable TLS configuration                                                                             |
| ``ONEAPP_RABBITMQ_PORT_TLS``       |  ``5671``     | Port on which RabbitMQ listens for SSL connections                                                   |
| ``ONEAPP_RABBITMQ_TLS_CERT``       |  ````         | Server certificate (base64 .pem)                                                                     |
| ``ONEAPP_RABBITMQ_TLS_KEY``        |  ````         | Server certficate key (base64 .key)                                                                  |
| ``ONEAPP_RABBITMQ_TLS_PASS``       |  ````         | Server certificate password                                                                          |
| ``ONEAPP_RABBITMQ_TLS_CA``         |  ````         | CA certificate chain                                                                                 |



- Service credentials: By default, if not defined, the user generated for RabbitMQ will be "rabbitadmin" and its password will be automatically generated. You can find this information in /etc/one-appliance/config on the appliance.


## TLS Configuration

When the parameter ``ONEAPP_RABBITMQ_TLS_ENABLED="YES"`` is set, the appliance will configure the RabbitMQ deployment to use TLS.

The appliance will create the folder ``/opt/rabbitmq/certs`` and three files in that location: ``server.pem`` with the contents of ``ONEAPP_RABBITMQ_TLS_CERT``, ``server.key`` with the contents of ``ONEAPP_RABBITMQ_TLS_KEY`` and ``ca.pem`` with the contents of ``ONEAPP_RABBITMQ_TLS_CA``. If either of those variables is empty, the scripts will autogenerate new certificates using the openssl tools.

> [!Note]
> On recontextualization the scripts will skip the certificate creation if ``server.pem`` or ``server.key`` are present in ``/opt/rabbitmq/certs``. In order to update the certificates it would be necessary to first manually delete the existing ones and then recontext the VM.

# Quick Start

After downloading the appliance from Marketplace, follow this steps to have a basic RabbitMQ instance with basic configuration.

Steps to deploy a RabbitMQ instance:

1. Download the RabbitMQ appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.
   ```
   $ onemarketapp export 'RabbitMQ' rabbitmq --datastore default
   ```

2. Adjust the VM template as desired (i.e. CPU, MEMORY, number of disks). It should look similar to this:
   ```
   CONTEXT=[
      NETWORK="YES",
      ONEAPP_RABBITMQ_LOOPBACK_USER="$ONEAPP_RABBITMQ_LOOPBACK_USER",
      ONEAPP_RABBITMQ_PASS="$ONEAPP_RABBITMQ_PASS",
      ONEAPP_RABBITMQ_TLS_CA="$ONEAPP_RABBITMQ_TLS_CA",
      ONEAPP_RABBITMQ_TLS_CERT="$ONEAPP_RABBITMQ_TLS_CERT",
      ONEAPP_RABBITMQ_TLS_ENABLED="$ONEAPP_RABBITMQ_TLS_ENABLED",
      ONEAPP_RABBITMQ_TLS_KEY="$ONEAPP_RABBITMQ_TLS_KEY",
      ONEAPP_RABBITMQ_TLS_PASS="$ONEAPP_RABBITMQ_TLS_PASS",
      ONEAPP_RABBITMQ_USER="$ONEAPP_RABBITMQ_USER",
      SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]" ]
   CPU="1"
   DISK=[
      IMAGE_ID="48" ]
   GRAPHICS=[
   LISTEN="0.0.0.0",
   TYPE="vnc" ]
   INPUTS_ORDER="ONEAPP_RABBITMQ_USER,ONEAPP_RABBITMQ_PASS,ONEAPP_RABBITMQ_LOOPBACK_USER,ONEAPP_RABBITMQ_TLS_ENABLED,ONEAPP_RABBITMQ_TLS_CERT,ONEAPP_RABBITMQ_TLS_KEY,ONEAPP_RABBITMQ_TLS_PASS,ONEAPP_RABBITMQ_TLS_CA"
   MEMORY="1024"
   OS=[
   ARCH="x86_64" ]
   USER_INPUTS=[
      ONEAPP_RABBITMQ_LOOPBACK_USER="M|boolean|Enable remote admin access| |YES",
      ONEAPP_RABBITMQ_PASS="O|password|RabbitMQ admin user password",
      ONEAPP_RABBITMQ_TLS_CA="O|text64|RabbitMQ CA chain (.pem)",
      ONEAPP_RABBITMQ_TLS_CERT="O|text64|RabbitMQ server certificate (.pem)",
      ONEAPP_RABBITMQ_TLS_ENABLED="M|boolean|Enable TLS configuration| |NO",
      ONEAPP_RABBITMQ_TLS_KEY="O|text64|RabbitMQ server key (.key)",
      ONEAPP_RABBITMQ_TLS_PASS="O|password|RabbitMQ server key password",
      ONEAPP_RABBITMQ_USER="O|text|RabbitMQ admin user| |rabbitadmin" ]
   ```
3. Instantiate RabbitMQ template:
   ```
   $ onetemplate instantiate rabbitmq
   ```
   This will prompt the user for the contextualization parameters.

4. Attach a new NIC to the VM:
   ```
   $ onevm nic-atttach VM_ID --network VNET_ID
   ```
5. Access your new RabbitMQ instance and check rabbitmq-server is working:
   ```
   $ onevm ssh VM_ID

   root@rabbitm:~# rabbitmqctl list_queues
   ```

# Features

This appliance comes with RabbitMQ installed globally, following RabbitMQ [official install guide](https://www.rabbitmq.com/docs/install-debian), including the following features:

- Based on the latest RabbitMQ release (4.0.7-1) on Ubuntu 22.04 LTS
- Configuration file in ``/etc/rabbitmq/rabbitmq.conf``
- TLS configuration with self generated certificates.

## Contextualization

The contextualization parameters ([CONTEXT section](https://docs.opennebula.io/stable/management_and_operations)) in the VM template controls the configuration of the service, see the table below

| Parameter                          | Default       | Description                                                                                          |
| ---------------------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| ``ONEAPP_RABBITMQ_NODE_PORT``      | ``5672``      | Port on which the RabbitMQ node will listen for connections                                          |
| ``ONEAPP_RABBITMQ_LOOPBACK_USER``  | ``false``     | Allow the user to connect remotely                                                                   |
| ``ONEAPP_RABBITMQ_USER``   	     | ``rabbitadmin``  | User for RabbitMQ service                                                                         |
| ``ONEAPP_RABBITMQ_PASS``  	     | ``<random>``  | Password for RabbitMQ service                                                                        |
| ``ONEAPP_RABBITMQ_LOG_LEVEL``      |  ``info``     | Controls the granularity of logging  {info,debug}                                                    |
| ``ONEAPP_RABBITMQ_TLS_ENABLED``    |  ``NO``       | Enable TLS configuration                                                                             |
| ``ONEAPP_RABBITMQ_PORT_TLS``       |  ``5672``     | Port on which RabbitMQ listens for SSL connections                                                   |
| ``ONEAPP_RABBITMQ_TLS_CERT``       |  ````         | Server certificate (base64 .pem)                                                                     |
| ``ONEAPP_RABBITMQ_TLS_KEY``        |  ````         | Server certficate key (base64 .key)                                                                  |
| ``ONEAPP_RABBITMQ_TLS_PASS``       |  ````         | Server certificate password                                                                          |
| ``ONEAPP_RABBITMQ_TLS_CA``         |  ````         | CA certificate chain                                                                                 |



- Service credentials: By default, if not defined, the user generated for RabbitMQ will be "rabbitadmin" and its password will be automatically generated. You can find this information in /etc/one-appliance/config on the appliance.


## TLS Configuration

When the parameter ``ONEAPP_RABBITMQ_TLS_ENABLED="YES"`` is set, the appliance will configure the RabbitMQ deployment to use TLS.

The appliance will create the folder ``/opt/rabbitmq/certs`` and three files in that location: ``server.pem`` with the contents of ``ONEAPP_RABBITMQ_TLS_CERT``, ``server.key`` with the contents of ``ONEAPP_RABBITMQ_TLS_KEY`` and ``ca.pem`` with the contents of ``ONEAPP_RABBITMQ_TLS_CA``. If either of those variables is empty, the scripts will autogenerate new certificates using the openssl tools.

> [!Note]
> On recontextualization the scripts will skip the certificate creation if ``server.pem`` or ``server.key`` are present in ``/opt/rabbitmq/certs``. In order to update the certificates it would be necessary to first manually delete the existing ones and then recontext the VM.
