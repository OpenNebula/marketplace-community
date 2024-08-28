import os
import pyone
import argparse

# Define default value for the location of the file with OpenNebula credentials
oneAuthPath = os.path.expanduser('~') + '/.one/one_auth'

# Get default path to the file with OpenNebula credentials
credFile = os.getenv('ONE_AUTH', oneAuthPath)

# Read script arguments
parser = argparse.ArgumentParser(description = 'Instantiate VM from specified Template ID to run certification tests.')
parser.add_argument('template_id', type = int, help='VM template ID to instantiate a VM from')
parser.add_argument('-n','--vm_name', default = 'app_cert_test', help = 'VM name (default: app_cert_test)')
parser.add_argument('-r','--read-file', default = credFile, help = 'read credentials from file (default: read from the file pointed by $ONE_AUTH)')
parser.add_argument('-e','--endpoint', default = 'http://localhost:2633/RPC2', help = 'URL of OpenNebula xmlrpc frontend  (default: http://localhost:2633/RPC2)')
args = parser.parse_args()

credFilePath = args.read_file 
endpoint = args.endpoint

# Check if the specified path to the file with OpenNebula credentials exists
if not os.path.isfile(credFilePath) or not os.access(credFilePath, os.R_OK):
    print('Either the file',credFilePath, 'is missing or not readable. Please, check if it exists and is accessible. Exiting')
    exit()

f = open(credFilePath, "r")
creds = f.readline().replace('\n','')

one = pyone.OneServer(endpoint, session = creds)

templateId = args.template_id
vmName = args.vm_name
vm = one.template.instantiate(templateId,vmName)
print ('The ID of the Instantiated VM is',vm)

# Close the file with OpenNebula credentials
f.close()
