*** Settings ***
Documentation       This resource file contains the basic requests used by Capif. NGINX_HOSTNAME and CAPIF_AUTH can be set as global variables, depends on environment used

Library             Collections
Library             String
Library             /opt/robot-tests/tests/libraries/bodyRequests.py

*** Keywords ***
Create Events From InvocationLogs
    [Arguments]
    ...    ${subscription_id}
    ...    ${invocation_log}
    ...    ${events_expected}=${NONE}
    ...    ${event_detail_expected}=${TRUE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END

    # Now we create the expected events received at notification server according to logs sent to loggin service in order to check if all are present.
    ${invocation_log_base}=    Copy Dictionary    ${invocation_log}    deepcopy=True
    # Store log array because each log will be notified in one Event Notification
    ${invocation_log_logs}=    Copy List    ${invocation_log_base['logs']}
    # Remove logs array from invocationLog data
    Remove From Dictionary    ${invocation_log_base}    logs

    FOR    ${log}    IN    @{invocation_log_logs}
        Log Dictionary    ${log}
        ${invocation_logs}=    Copy Dictionary    ${invocation_log_base}    deepcopy=True

        # Get Event Enum for this result
        ${event_enum}=    Set Variable
        IF    ${log['result']} >= 200 and ${log['result']} < 300
            ${event_enum}=    Set Variable    SERVICE_API_INVOCATION_SUCCESS
        ELSE
            ${event_enum}=    Set Variable    SERVICE_API_INVOCATION_FAILURE
        END
        # Create a log array with only one component
        ${log_list}=    Create List    ${log}
        # Setup logs array with previously created list
        Set To Dictionary    ${invocation_logs}    logs=${log_list}
        IF    "${event_detail_expected}" != "${TRUE}"
            ${invocation_logs}=    Set Variable    ${NONE}
        END
        ${event_expected}=    Create Notification Event
        ...    ${subscription_id}
        ...    ${event_enum}
        ...    invocationLogs=${invocation_logs}
        Append To List    ${events_expected}    ${event_expected}
    END

    RETURN    ${events_expected}

Create Expected Events For Service API Notifications
    [Arguments]
    ...    ${subscription_id}
    ...    ${service_api_available_resources}=${NONE}
    ...    ${service_api_unavailable_resources}=${NONE}
    ...    ${events_expected}=${NONE}
    ...    ${event_detail_expected}=${FALSE}
    ...    ${service_api_description_expected}=${FALSE}
    ...    ${service_api_description}=${NONE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END

    ${service_api_description_to_use}=   Set Variable   ${NONE}
    IF    "${service_api_description_expected}" == "${TRUE}"
        IF   "${service_api_description}" == "${NONE}"
            LOG   service_api_description is expected but serviceApiDescription is set to None     ERROR
            Fail   service_api_description is expected but serviceApiDescription is set to None, review Test ${TEST_NAME}
        ELSE
            ${service_api_description_to_use}=   Set Variable   ${service_api_description}
        END
    END

    IF   "${service_api_available_resources}" != "${NONE}"
        FOR    ${service_api_available_resource}    IN    @{service_api_available_resources}
            Log    ${service_api_available_resource}
            ${api_id}=    Fetch From Right    ${service_api_available_resource.path}    /

            IF    "${event_detail_expected}" != "${TRUE}"
                ${api_id}=    Set Variable    ${NONE}
            END

            ${event_expected}=    Create Notification Event
            ...    ${subscription_id}
            ...    SERVICE_API_AVAILABLE
            ...    apiIds=${api_id}
            ...    serviceAPIDescriptions=${service_api_description_to_use}
            Append To List    ${events_expected}    ${event_expected}
        END
    END

    IF   "${service_api_unavailable_resources}" != "${NONE}"
        FOR    ${service_api_unavailable_resource}    IN    @{service_api_unavailable_resources}
            Log    ${service_api_unavailable_resource}
            ${api_id}=    Fetch From Right    ${service_api_unavailable_resource.path}    /
            IF    "${event_detail_expected}" != "${TRUE}"
                ${api_id}=    Set Variable    ${NONE}
            END
            ${event_expected}=    Create Notification Event
            ...    ${subscription_id}
            ...    SERVICE_API_UNAVAILABLE
            ...    apiIds=${api_id}
            ...    serviceAPIDescriptions=${service_api_description_to_use}
            Append To List    ${events_expected}    ${event_expected}
        END
    END

    RETURN    ${events_expected}

Create Expected Api Invoker Events
    [Arguments]
    ...    ${subscription_id}
    ...    ${api_invoker_onboarded_resources}=${NONE}
    ...    ${api_invoker_updated_resources}=${NONE}
    ...    ${api_invoker_offboarded_resources}=${NONE}
    ...    ${events_expected}=${NONE}
    ...    ${event_detail_expected}=${TRUE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END

    # Create Notification Events expected to be received for Onboarded event
    IF   "${api_invoker_onboarded_resources}" != "${NONE}"
        FOR    ${api_invoker_onboarded_resource}    IN    @{api_invoker_onboarded_resources}
            Log    ${api_invoker_onboarded_resource}
            ${api_invoker_id}=    Fetch From Right    ${api_invoker_onboarded_resource.path}    /

            IF    "${event_detail_expected}" != "${TRUE}"
                ${api_invoker_id}=    Set Variable    ${NONE}
            END

            ${event_expected}=    Create Notification Event
            ...    ${subscription_id}
            ...    API_INVOKER_ONBOARDED
            ...    apiInvokerIds=${api_invoker_id}
            Append To List    ${events_expected}    ${event_expected}
        END
    END

    # Create Notification Events expected to be received for Updated event
    IF   "${api_invoker_updated_resources}" != "${NONE}"
        FOR    ${api_invoker_updated_resource}    IN    @{api_invoker_updated_resources}
            Log    ${api_invoker_updated_resource}
            ${api_invoker_id}=    Fetch From Right    ${api_invoker_updated_resource.path}    /

            IF    "${event_detail_expected}" != "${TRUE}"
                ${api_invoker_id}=    Set Variable    ${NONE}
            END

            ${event_expected}=    Create Notification Event
            ...    ${subscription_id}
            ...    API_INVOKER_UPDATED
            ...    apiInvokerIds=${api_invoker_id}
            Append To List    ${events_expected}    ${event_expected}
        END
    END

    # Create Notification Events expected to be received for Offboarded event
    IF   "${api_invoker_offboarded_resources}" != "${NONE}"
        FOR    ${api_invoker_offboarded_resource}    IN    @{api_invoker_offboarded_resources}
            Log    ${api_invoker_offboarded_resource}
            ${api_invoker_id}=    Fetch From Right    ${api_invoker_offboarded_resource.path}    /

            IF    "${event_detail_expected}" != "${TRUE}"
                ${api_invoker_id}=    Set Variable    ${NONE}
            END

            ${event_expected}=    Create Notification Event
            ...    ${subscription_id}
            ...    API_INVOKER_OFFBOARDED
            ...    apiInvokerIds=${api_invoker_id}
            Append To List    ${events_expected}    ${event_expected}
        END
    END

    RETURN    ${events_expected}

Create Expected Access Control Policy Update Event
    [Arguments]
    ...    ${subscription_id}
    ...    ${service_api_id}
    ...    ${api_invoker_policies}
    ...    ${events_expected}=${NONE}
    ...    ${event_detail_expected}=${TRUE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END
    ${acc_ctrl_pol_list}=    Create Dictionary    apiId=${service_api_id}    apiInvokerPolicies=${api_invoker_policies}
    Check Variable    ${acc_ctrl_pol_list}    AccessControlPolicyListExt

    IF    "${event_detail_expected}" != "${TRUE}"
        ${acc_ctrl_pol_list}=    Set Variable    ${NONE}
    END

    ${event_expected}=    Create Notification Event
    ...    ${subscription_id}
    ...    ACCESS_CONTROL_POLICY_UPDATE
    ...    accCtrlPolList=${acc_ctrl_pol_list}
    Append To List    ${events_expected}    ${event_expected}

    RETURN    ${events_expected}

Create Expected Access Control Policy Unavailable
    [Arguments]    ${subscription_id}
    ...    ${events_expected}=${NONE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END
    ${event_expected}=    Create Notification Event
    ...    ${subscription_id}
    ...    ACCESS_CONTROL_POLICY_UNAVAILABLE
    Append To List    ${events_expected}    ${event_expected}

    RETURN    ${events_expected}

Create Expected Api Invoker Authorization Revoked
    [Arguments]    ${subscription_id}    ${events_expected}=${NONE}
    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END
    ${event_expected}=    Create Notification Event
    ...    ${subscription_id}
    ...    API_INVOKER_AUTHORIZATION_REVOKED
    Append To List    ${events_expected}    ${event_expected}
    RETURN    ${events_expected}

Create Expected Service Update Event
    [Arguments]
    ...    ${subscription_id}
    ...    ${service_api_resource}
    ...    ${service_api_descriptions}
    ...    ${events_expected}=${NONE}
    ...    ${event_detail_expected}=${TRUE}

    IF    ${events_expected} == ${NONE}
        ${events_expected}=    Create List
    END
    ${api_id}=    Fetch From Right    ${service_api_resource.path}    /
    Set To Dictionary    ${service_api_descriptions}    apiId=${api_id}

    IF    "${event_detail_expected}" != "${TRUE}"
        ${service_api_descriptions}=    Set Variable    ${NONE}
    END

    ${event_expected}=    Create Notification Event
    ...    ${subscription_id}
    ...    SERVICE_API_UPDATE
    ...    serviceAPIDescriptions=${service_api_descriptions}
    Append To List    ${events_expected}    ${event_expected}
    RETURN    ${events_expected}
