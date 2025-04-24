*** Settings ***
Documentation       This resource file contains the basic requests used by Capif. NGINX_HOSTNAME and CAPIF_AUTH can be set as global variables, depends on environment used

Library             RequestsLibrary
Library             Collections
Library             OperatingSystem
Library             XML
Library             Telnet
Library             String


*** Variables ***
${CAPIF_AUTH}                           ${EMPTY}
${CAPIF_BEARER}                         ${EMPTY}

${LOCATION_INVOKER_RESOURCE_REGEX}
...                                     ^/api-invoker-management/v1/onboardedInvokers/[0-9a-zA-Z]+
${LOCATION_EVENT_RESOURCE_REGEX}
...                                     ^/capif-events/v1/[0-9a-zA-Z]+/subscriptions/[0-9a-zA-Z]+
${LOCATION_INVOKER_RESOURCE_REGEX}
...                                     ^/api-invoker-management/v1/onboardedInvokers/[0-9a-zA-Z]+
${LOCATION_PUBLISH_RESOURCE_REGEX}
...                                     ^/published-apis/v1/[0-9a-zA-Z]+/service-apis/[0-9a-zA-Z]+
${LOCATION_SECURITY_RESOURCE_REGEX}
...                                     ^/capif-security/v1/trustedInvokers/[0-9a-zA-Z]+
${LOCATION_PROVIDER_RESOURCE_REGEX}
...                                     ^/api-provider-management/v1/registrations/[0-9a-zA-Z]+
${LOCATION_LOGGING_RESOURCE_REGEX}
...                                     ^/api-invocation-logs/v1/[0-9a-zA-Z]+/logs/[0-9a-zA-Z]+

${INVOKER_ROLE}                         invoker
${AMF_ROLE}                             amf
${APF_ROLE}                             apf
${AEF_ROLE}                             aef


*** Keywords ***
