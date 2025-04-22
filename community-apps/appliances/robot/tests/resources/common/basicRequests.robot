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
Create CAPIF Session
    [Documentation]    Create needed session and headers.
    ...    If server input data is set to NONE, it will try to use NGINX_HOSTNAME variable.
    [Arguments]    ${server}=${NONE}    ${access_token}=${NONE}    ${verify}=${NONE}    ${vault_token}=${NONE}

    IF    "${server}" != "${NONE}"
        Create Session    apisession    ${server}    verify=${verify}
    END

    ${headers}=    Create Dictionary
    IF    "${access_token}" != "${NONE}"
        ${headers}=    Create Dictionary    Authorization=Bearer ${access_token}
    END

    IF    "${vault_token}" != "${NONE}"
        ${headers}=    Create Dictionary    X-Vault-Token    ${vault_token}
    END

    RETURN    ${headers}

Create Register Admin Session
    [Documentation]    Create needed session to reach Register as Administrator.
    [Arguments]    ${server}=${NONE}    ${access_token}=${NONE}    ${verify}=${NONE}    ${vault_token}=${NONE}
    IF    "${server}" != "${NONE}"
        IF    "${access_token}" != "${NONE}"
            ## Return Header with bearer
            ${headers}=    Create Dictionary    Authorization=Bearer ${access_token}

            RETURN    ${headers}
        END

        # Request Admin Login to retrieve access token
        Create Session    register_session    ${server}    verify=${verify}    disable_warnings=1

        ${auth}=    Set variable    ${{ ('${REGISTER_ADMIN_USER}','${REGISTER_ADMIN_PASSWORD}') }}
        ${resp}=    POST On Session    register_session    /login    auth=${auth}

        Log Dictionary    ${resp.json()}

        ## Crear sesión con token
        ${headers}=    Create Dictionary    Authorization=Bearer ${resp.json()['access_token']}

        RETURN    ${headers}
    END

    RETURN    ${NONE}

## NEW REQUESTS TO REGISTER

Post Request Admin Register
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${json}=${NONE}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}
    ...    ${data}=${NONE}

    ${headers}=    Create Register Admin Session    ${server}    ${access_token}    ${verify}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    POST On Session
    ...    register_session
    ...    ${endpoint}
    ...    headers=${headers}
    ...    json=${json}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    ...    data=${data}
    RETURN    ${resp}

Get Request Admin Register
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create Register Admin Session    ${server}    ${access_token}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    GET On Session
    ...    register_session
    ...    ${endpoint}
    ...    headers=${headers}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    RETURN    ${resp}

Delete User Admin Register Request
    [Arguments]    ${user_uuid}
    ${headers}=    Create Register Admin Session    ${CAPIF_HTTPS_REGISTER_URL}    verify=False
    ${resp}=    DELETE On Session    register_session    /deleteUser/${user_uuid}    headers=${headers}
    RETURN    ${resp}

# NEW REQUESTS END

Post Request Capif
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${json}=${NONE}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}
    ...    ${data}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}    ${verify}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    POST On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    json=${json}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    ...    data=${data}
    RETURN    ${resp}

Get Request Capif
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    GET On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    RETURN    ${resp}

Get CA Vault
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}    vault_token=${CAPIF_VAULT_TOKEN}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    GET On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    RETURN    ${resp}

Obtain Superadmin Cert From Vault
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}    vault_token=${CAPIF_VAULT_TOKEN}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${csr_request}=    Create User Csr    ${SUPERADMIN_USERNAME}    cn=superadmin
    ${json}=    Vault Sign Superadmin Certificate Body    ${csr_request}

    ${resp}=    Post On Session
    ...    apisession
    ...    ${endpoint}
    ...    json=${json}
    ...    headers=${headers}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}
    RETURN    ${resp}

Put Request Capif
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${json}=${NONE}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    PUT On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    json=${json}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}

    RETURN    ${resp}

Patch Request Capif
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${json}=${NONE}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}

    Set To Dictionary    ${headers}    Content-Type    application/merge-patch+json

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    PATCH On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    json=${json}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}

    RETURN    ${resp}

Delete Request Capif
    [Timeout]    ${REQUESTS_TIMEOUT}
    [Arguments]
    ...    ${endpoint}
    ...    ${server}=${NONE}
    ...    ${access_token}=${NONE}
    ...    ${auth}=${NONE}
    ...    ${verify}=${FALSE}
    ...    ${cert}=${NONE}
    ...    ${username}=${NONE}

    ${headers}=    Create CAPIF Session    ${server}    ${access_token}

    IF    '${username}' != '${NONE}'
        ${cert}=    Set variable    ${{ ('${username}.crt','${username}.key') }}
    END

    ${resp}=    DELETE On Session
    ...    apisession
    ...    ${endpoint}
    ...    headers=${headers}
    ...    expected_status=any
    ...    verify=${verify}
    ...    cert=${cert}

    RETURN    ${resp}

Register User At Jwt Auth
    [Arguments]    ${username}    ${role}    ${password}=password    ${description}=Testing

    ${cn}=    Set Variable    ${username}
    # Create certificate and private_key for this machine.
    IF    "${role}" == "${INVOKER_ROLE}"
        ${cn}=    Set Variable    invoker
        ${csr_request}=    Create User Csr    ${username}    ${cn}
        Log    inside if cn=${cn}
    ELSE
        ${csr_request}=    Set Variable    ${None}
    END

    Log    cn=${cn}

    ${resp}=    Create User At Register
    ...    ${username}
    ...    ${password}
    ...    ${description}
    ...    email="${username}@nobody.com"

    ${get_auth_response}=    Get Auth For User    ${username}    ${password}

    Log Dictionary    ${get_auth_response}

    ${register_user_info}=    Create Dictionary
    ...    netappID=${resp.json()['uuid']}
    ...    csr_request=${csr_request}
    ...    &{resp.json()}
    ...    &{get_auth_response}

    Log Dictionary    ${register_user_info}

    IF    "ca_root" in @{register_user_info.keys()}
        Store In File    ca.crt    ${register_user_info['ca_root']}
    END

    IF    "cert" in @{register_user_info.keys()}
        Store In File    ${username}.crt    ${register_user_info['cert']}
    END
    IF    "private_key" in @{register_user_info.keys()}
        Store In File    ${username}.key    ${register_user_info['private_key']}
    END

    Call Method    ${CAPIF_USERS}    update_register_users    ${register_user_info['uuid']}    ${username}

    RETURN    ${register_user_info}

Register User At Jwt Auth Provider
    [Arguments]
    ...    ${username}
    ...    ${password}=password
    ...    ${description}=Testing
    ...    ${total_apf_roles}=1
    ...    ${total_aef_roles}=1
    ...    ${total_amf_roles}=1

    ${apf_roles}=    Create Dictionary
    ${default_apf_username}=    Set Variable    APF_${username}
    FOR    ${index}    IN RANGE    ${total_apf_roles}
        ${apf_username}=    Set Variable    ${default_apf_username}_${index}
        IF    ${index} == 0
            ${apf_username}=    Set Variable    ${default_apf_username}
        END
        ${apf_csr_request}=    Create User Csr    ${apf_username}    apf
        ${apf_role}=
        ...    Create Dictionary
        ...    username=${apf_username}
        ...    csr_request=${apf_csr_request}
        ...    role=APF
        Set To Dictionary    ${apf_roles}    ${apf_username}=${apf_role}
    END

    ${aef_roles}=    Create Dictionary
    ${default_aef_username}=    Set Variable    AEF_${username}
    FOR    ${index}    IN RANGE    ${total_aef_roles}
        ${aef_username}=    Set Variable    ${default_aef_username}_${index}
        IF    ${index} == 0
            ${aef_username}=    Set Variable    ${default_aef_username}
        END
        ${aef_csr_request}=    Create User Csr    ${aef_username}    aef
        ${aef_role}=
        ...    Create Dictionary
        ...    username=${aef_username}
        ...    csr_request=${aef_csr_request}
        ...    role=AEF
        Set To Dictionary    ${aef_roles}    ${aef_username}=${aef_role}
    END

    ${amf_roles}=    Create Dictionary
    ${default_amf_username}=    Set Variable    AMF_${username}
    FOR    ${index}    IN RANGE    ${total_amf_roles}
        ${amf_username}=    Set Variable    ${default_amf_username}_${index}
        IF    ${index} == 0
            ${amf_username}=    Set Variable    ${default_amf_username}
        END
        ${amf_csr_request}=    Create User Csr    ${amf_username}    amf
        ${amf_role}=
        ...    Create Dictionary
        ...    username=${amf_username}
        ...    csr_request=${amf_csr_request}
        ...    role=AMF
        Set To Dictionary    ${amf_roles}    ${amf_username}=${amf_role}
    END

    # Create a certificate for each kind of role under provider
    ${csr_request}=    Create User Csr    ${username}    provider

    # Register provider
    ${resp}=    Create User At Register
    ...    ${username}
    ...    ${password}
    ...    ${description}
    ...    email="${username}@nobody.com"

    ${get_auth_response}=    Get Auth For User    ${username}    ${password}

    Log Dictionary    ${get_auth_response}

    ${register_user_info}=    Create Dictionary
    ...    netappID=${resp.json()['uuid']}
    ...    csr_request=${csr_request}
    ...    apf_username=${default_apf_username}
    ...    aef_username=${default_aef_username}
    ...    amf_username=${default_amf_username}
    ...    apf_csr_request=${apf_roles['${default_apf_username}']['csr_request']}
    ...    aef_csr_request=${aef_roles['${default_aef_username}']['csr_request']}
    ...    amf_csr_request=${amf_roles['${default_amf_username}']['csr_request']}
    ...    apf_roles=${apf_roles}
    ...    aef_roles=${aef_roles}
    ...    amf_roles=${amf_roles}
    ...    &{resp.json()}
    ...    &{get_auth_response}

    Log Dictionary    ${register_user_info}

    Call Method    ${CAPIF_USERS}    update_register_users    ${register_user_info['uuid']}    ${username}

    RETURN    ${register_user_info}

Login Register Admin
    ${headers}=    Create Register Admin Session    ${CAPIF_HTTPS_REGISTER_URL}
    RETURN    ${headers}

Create User At Register
    [Documentation]    (Administrator) This Keyword create a user at register component.
    [Arguments]    ${username}    ${password}    ${description}    ${email}

    # Obtain Admin Token to request creation of User
    ${headers}=    Login Register Admin

    &{body}=    Create Dictionary
    ...    username=${username}
    ...    password=${password}
    ...    description=${description}
    ...    email=${email}
    ...    enterprise=enterprise
    ...    country=Spain
    ...    purpose=testing
    ...    phone_number=123456789
    ...    company_web=www.enterprise.com
    ${resp}=    Post On Session    register_session    /createUser    headers=${headers}    json=${body}
    Should Be Equal As Strings    ${resp.status_code}    201

    RETURN    ${resp}

Delete User At Register
    [Documentation]    (Administrator) This Keyword delete a user from register.
    [Arguments]    ${username}=${NONE}    ${uuid}=${NONE}
    ${user_uuid}=    Set Variable    ${uuid}
    ${environment_users}=    Set Variable    ${TRUE}

    IF    "${username}" != "${NONE}"
        ${user_uuid}=    Call Method    ${CAPIF_USERS}    get_user_uuid    ${username}
    END

    IF    "${user_uuid}" == "${NONE}"
        ${user_uuid}=    Get User Uuid At Register    ${username}
        ${environment_users}=    Set Variable    ${FALSE}
    END

    ${resp}=    Delete User Admin Register Request    ${user_uuid}

    Should Be Equal As Strings    ${resp.status_code}    204

    IF    ${environment_users}
        Call Method    ${CAPIF_USERS}    remove_register_users_entry    ${user_uuid}
    END

    RETURN    ${resp}

Get List of Users At Register
    [Documentation]    (Administrator) This Keyword retrieve a list of users from register.
    ${headers}=    Create Register Admin Session    ${CAPIF_HTTPS_REGISTER_URL}    verify=False

    ${resp}=    GET On Session    register_session    /getUsers    headers=${headers}

    Should Be Equal As Strings    ${resp.status_code}    200

    RETURN    ${resp.json()['users']}

Get User Uuid At Register
    [Documentation]    (Administrator) This Keyword retrieve a list of users and search uuid of user passed by parameters
    [Arguments]    ${username}
    ${users}=    Get List of Users At Register

    # Find the first user with username indicated
    ${user_uuid}=    Set Variable    &{EMPTY}
    FOR    ${user}    IN    @{users}
        IF    "${user['username']}" == "${username}"
            ${user_uuid}=    Set Variable    ${user['uuid']}
            BREAK
        END
    END

    IF    "${user_uuid}" == "${EMPTY}"
        Log    ${username} not found in Register
    END

    RETURN    ${user_uuid}

Get Auth For User
    [Documentation]    (User) This Keyword retrieve token to be used by user towards first interaction with CCF.
    [Arguments]    ${username}    ${password}
    ${auth}=    Set variable    ${{ ('${username}','${password}') }}
    ${resp}=    GET On Session    register_session    /getauth    auth=${auth}

    Should Be Equal As Strings    ${resp.status_code}    200
    Log Dictionary    ${resp.json()}

    RETURN    ${resp.json()}

Clean Test Information
    ${capif_users_dict}=    Call Method    ${CAPIF_USERS}    get_capif_users_dict

    ${register_users_dict}=    Call Method    ${CAPIF_USERS}    get_register_users_dict

    ${keys}=    Get Dictionary Keys    ${capif_users_dict}

    FOR    ${key}    IN    @{keys}
        ${value}=    Get From Dictionary    ${capif_users_dict}    ${key}
        ${resp}=    Delete Request Capif
        ...    ${key}
        ...    server=${CAPIF_HTTPS_URL}
        ...    verify=ca.crt
        ...    username=${value}

        Status Should Be    204    ${resp}

        Call Method    ${CAPIF_USERS}    remove_capif_users_entry    ${key}
    END

    ${uuids}=    Get Dictionary Keys    ${register_users_dict}
    FOR    ${uuid}    IN    @{uuids}
        Delete User At Register    uuid=${uuid}
    END

Remove entity
    [Arguments]    ${entity_user}    ${certificate_name}=${entity_user}

    ${capif_users_dict}=    Call Method    ${CAPIF_USERS}    get_capif_users_dict

    ${register_users_dict}=    Call Method    ${CAPIF_USERS}    get_register_users_dict

    Log Dictionary    ${capif_users_dict}
    Log Dictionary    ${register_users_dict}
    ${keys}=    Get Dictionary Keys    ${capif_users_dict}

    FOR    ${key}    IN    @{keys}
        ${value}=    Get From Dictionary    ${capif_users_dict}    ${key}
        IF    "${value}" == "${certificate_name}"
            ${resp}=    Delete Request Capif
            ...    ${key}
            ...    server=${CAPIF_HTTPS_URL}
            ...    verify=ca.crt
            ...    username=${value}

            Status Should Be    204    ${resp}

            Call Method    ${CAPIF_USERS}    remove_capif_users_entry    ${key}
        END
    END

    Delete User At Register    username=${entity_user}

    Log Dictionary    ${capif_users_dict}
    Log Dictionary    ${register_users_dict}

Remove Resource
    [Arguments]    ${resource_url}    ${management_cert}    ${username}

    ${resp}=    Delete Request Capif
    ...    ${resource_url}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${management_cert}

    Run Keyword and Continue On Failure    Status Should Be    204    ${resp}

    Delete User At Register    username=${username}

    Should Be Equal As Strings    ${resp.status_code}    204

Invoker Default Onboarding
    [Arguments]    ${invoker_username}=${INVOKER_USERNAME}
    ${register_user_info}=    Register User At Jwt Auth
    ...    username=${invoker_username}    role=${INVOKER_ROLE}

    # Send Onboarding Request
    ${request_body}=    Create Onboarding Notification Body
    ...    http://${CAPIF_CALLBACK_IP}:${CAPIF_CALLBACK_PORT}/netapp_callback
    ...    ${register_user_info['csr_request']}
    ...    ${invoker_username}
    ${resp}=    Post Request Capif
    ...    ${register_user_info['ccf_onboarding_url']}
    ...    json=${request_body}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    access_token=${register_user_info['access_token']}

    Set To Dictionary    ${register_user_info}    api_invoker_id=${resp.json()['apiInvokerId']}
    Log Dictionary    ${register_user_info}

    # Assertions
    Status Should Be    201    ${resp}
    Check Variable    ${resp.json()}    APIInvokerEnrolmentDetails
    ${resource_url}=    Check Location Header    ${resp}    ${LOCATION_INVOKER_RESOURCE_REGEX}
    # Store dummy signede certificate
    Store In File    ${invoker_username}.crt    ${resp.json()['onboardingInformation']['apiInvokerCertificate']}

    ${url}=    Parse Url    ${resp.headers['Location']}
    Call Method    ${CAPIF_USERS}    update_capif_users_dicts    ${url.path}    ${invoker_username}

    Set To Dictionary    ${register_user_info}    resource_url=${resource_url}
    Set To Dictionary    ${register_user_info}    management_cert=${invoker_username}

    RETURN    ${register_user_info}    ${url}    ${request_body}

Provider Registration
    [Arguments]    ${register_user_info}

    ${api_prov_funcs}=    Create List

    # Create provider Registration Body
    FOR    ${key}    ${value}    IN    &{register_user_info['apf_roles']}    &{register_user_info['aef_roles']}    &{register_user_info['amf_roles']}
        ${func_details}=    Create Api Provider Function Details
        ...    ${key}
        ...    ${value['csr_request']}
        ...    ${value['role']}
        Append To List    ${api_prov_funcs}    ${func_details}
    END

    ${request_body}=    Create Api Provider Enrolment Details Body
    ...    ${register_user_info['access_token']}
    ...    ${api_prov_funcs}

    # Register Provider
    ${resp}=    Post Request Capif
    ...    /api-provider-management/v1/registrations
    ...    json=${request_body}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    access_token=${register_user_info['access_token']}

    # Check Results
    Check Response Variable Type And Values    ${resp}    201    APIProviderEnrolmentDetails
    ${resource_url}=    Check Location Header    ${resp}    ${LOCATION_PROVIDER_RESOURCE_REGEX}

    Log Dictionary    ${resp.json()}

    FOR    ${prov}    IN    @{resp.json()['apiProvFuncs']}
        Log Dictionary    ${prov}
        Store In File    ${prov['apiProvFuncInfo']}.crt    ${prov['regInfo']['apiProvCert']}
        Log Dictionary    ${register_user_info}
        Log    ${register_user_info['apf_username']}
        IF    "${prov['apiProvFuncRole']}" == "APF"
            IF    "${prov['apiProvFuncInfo']}" == "${register_user_info['apf_username']}"
                Set To Dictionary    ${register_user_info}    apf_id=${prov['apiProvFuncId']}
            END
            Set To Dictionary
            ...    ${register_user_info['apf_roles']['${prov['apiProvFuncInfo']}']}
            ...    apf_id=${prov['apiProvFuncId']}
        ELSE IF    "${prov['apiProvFuncRole']}" == "AEF"
            IF    "${prov['apiProvFuncInfo']}" == "${register_user_info['aef_username']}"
                Set To Dictionary    ${register_user_info}    aef_id=${prov['apiProvFuncId']}
            END
            Set To Dictionary
            ...    ${register_user_info['aef_roles']['${prov['apiProvFuncInfo']}']}
            ...    aef_id=${prov['apiProvFuncId']}
        ELSE IF    "${prov['apiProvFuncRole']}" == "AMF"
            IF    "${prov['apiProvFuncInfo']}" == "${register_user_info['amf_username']}"
                Set To Dictionary    ${register_user_info}    amf_id=${prov['apiProvFuncId']}
            END
            Set To Dictionary
            ...    ${register_user_info['amf_roles']['${prov['apiProvFuncInfo']}']}
            ...    amf_id=${prov['apiProvFuncId']}
        ELSE
            Fail    "${prov['apiProvFuncRole']} is not valid role"
        END
    END

    Set To Dictionary
    ...    ${register_user_info}
    ...    provider_enrollment_details=${request_body}
    ...    resource_url=${resource_url}
    ...    provider_register_response=${resp}
    ...    management_cert=${register_user_info['amf_username']}

    Call Method
    ...    ${CAPIF_USERS}
    ...    update_capif_users_dicts
    ...    ${register_user_info['resource_url'].path}
    ...    ${register_user_info['amf_username']}

    RETURN    ${register_user_info}

Provider Default Registration
    [Arguments]
    ...    ${provider_username}=${PROVIDER_USERNAME}
    ...    ${total_apf_roles}=1
    ...    ${total_aef_roles}=1
    ...    ${total_amf_roles}=1
    ...    ${apf_id}=${NONE}
    ...    ${apf_username}=${NONE}

    # Register Provider
    ${register_user_info}=    Register User At Jwt Auth Provider
    ...    username=${provider_username}
    ...    total_apf_roles=${total_apf_roles}
    ...    total_aef_roles=${total_aef_roles}
    ...    total_amf_roles=${total_amf_roles}

    ${register_user_info}=    Provider Registration    ${register_user_info}

    Log Dictionary    ${register_user_info}

    RETURN    ${register_user_info}

Publish Service Api Request
    [Arguments]
    ...    ${register_user_info_provider}
    ...    ${service_name}=service_1
    ...    ${apf_id}=${NONE}
    ...    ${apf_username}=${NONE}
    ...    ${supported_features}=0
    ...    ${vendor_specific_service_api_description}=${None}
    ...    ${vendor_specific_aef_profile}=${None}
    ...    ${aef_id}=${NONE}
    ...    ${api_status}=${NONE}
    ...    ${security_methods}=default
    ...    ${domain_name}=${NONE}
    ...    ${interface_descriptions}=${NONE}

    ${aef_ids}=    Create List
    IF    "${aef_id}" == "${NONE}"
        Append To List    ${aef_ids}    ${register_user_info_provider['aef_id']}
    ELSE
        ${aef_ids}=   Set Variable     ${aef_id}
    END

    ${apf_id_to_use}=    Set Variable    ${register_user_info_provider['apf_id']}
    ${apf_username_to_use}=    Set Variable    ${register_user_info_provider['apf_username']}
    IF    "${apf_id}" != "${NONE}" and "${apf_id}" != "${register_user_info_provider['apf_id']}"
        FOR    ${apf_username}    ${apf_role}    IN    &{register_user_info_provider['apf_roles']}
            IF    "${apf_role['apf_id']}" == "${apf_id}"
                ${apf_id_to_use}=    Set Variable    ${apf_id}
                ${apf_username_to_use}=    Set Variable    ${apf_username}
                BREAK
            END
        END
    ELSE IF    "${apf_username}" != "${NONE}" and "${apf_username}" != "${register_user_info_provider['apf_username']}"
        ${apf_id_to_use}=    Set Variable    ${register_user_info_provider['apf_roles']['${apf_username}']['apf_id']}
        ${apf_username_to_use}=    Set Variable    ${apf_username}
    END

    ${request_body}=    Create Service Api Description
    ...    ${service_name}
    ...    ${aef_ids}
    ...    ${supported_features}
    ...    ${vendor_specific_service_api_description}
    ...    ${vendor_specific_aef_profile}
    ...    ${api_status}
    ...    ${security_methods}
    ...    ${domain_name}
    ...    ${interface_descriptions}

    ${resp}=    Post Request Capif
    ...    /published-apis/v1/${apf_id_to_use}/service-apis
    ...    json=${request_body}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${apf_username_to_use}

    RETURN    ${resp}   ${request_body}

Publish Service Api
    [Arguments]
    ...    ${register_user_info_provider}
    ...    ${service_name}=service_1
    ...    ${apf_id}=${NONE}
    ...    ${apf_username}=${NONE}
    ...    ${supported_features}=0
    ...    ${vendor_specific_service_api_description}=${None}
    ...    ${vendor_specific_aef_profile}=${None}
    ...    ${aef_id}=${NONE}
    ...    ${api_status}=${NONE}
    ...    ${security_methods}=default
    ...    ${domain_name}=${NONE}
    ...    ${interface_descriptions}=${NONE}

    ${resp}  ${request_body}=  Publish Service Api Request
    ...    ${register_user_info_provider}
    ...    ${service_name}
    ...    ${apf_id}
    ...    ${apf_username}
    ...    ${supported_features}
    ...    ${vendor_specific_service_api_description}
    ...    ${vendor_specific_aef_profile}
    ...    ${aef_id}
    ...    ${api_status}
    ...    ${security_methods}
    ...    ${domain_name}
    ...    ${interface_descriptions}

    Check Response Variable Type And Values    ${resp}    201    ServiceAPIDescription
    Dictionary Should Contain Key    ${resp.json()}    apiId
    ${resource_url}=    Check Location Header    ${resp}    ${LOCATION_PUBLISH_RESOURCE_REGEX}

    RETURN    ${resp.json()}    ${resource_url}    ${request_body}

Basic ACL registration
    [Arguments]    ${create_security_context}=${True}
    # Register APF
    ${register_user_info_provider}=    Provider Default Registration

    ${service_api_description_published}    ${resource_url}    ${request_body}=    Publish Service Api
    ...    ${register_user_info_provider}
    ...    service_1

    # Store apiId1
    ${serviceApiId}=    Set Variable    ${service_api_description_published['apiId']}

    # Retrieve Services 1
    ${resp}=    Get Request Capif
    ...    /published-apis/v1/${register_user_info_provider['apf_id']}/service-apis/${serviceApiId}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${APF_PROVIDER_USERNAME}

    Check Response Variable Type And Values    ${resp}    200    ServiceAPIDescription
    Dictionaries Should Be Equal    ${resp.json()}    ${service_api_description_published}

    # Default Invoker Registration and Onboarding
    ${register_user_info_invoker}    ${url}    ${request_body}=    Invoker Default Onboarding

    Call Method    ${CAPIF_USERS}    update_capif_users_dicts    ${url.path}    ${INVOKER_USERNAME}

    # Test
    ${discover_response}=    Get Request Capif
    ...    ${DISCOVER_URL}${register_user_info_invoker['api_invoker_id']}&aef-id=${register_user_info_provider['aef_id']}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${INVOKER_USERNAME}

    Check Response Variable Type And Values    ${discover_response}    200    DiscoveredAPIs

    IF    ${create_security_context} == ${True}
        # create Security Context
        ${request_body}=    Create Service Security From Discover Response
        ...    http://${CAPIF_HOSTNAME}:${CAPIF_HTTP_PORT}/test
        ...    ${discover_response}
        ${resp}=    Put Request Capif
        ...    /capif-security/v1/trustedInvokers/${register_user_info_invoker['api_invoker_id']}
        ...    json=${request_body}
        ...    server=${CAPIF_HTTPS_URL}
        ...    verify=ca.crt
        ...    username=${INVOKER_USERNAME}
        # Check Service Security
        Check Response Variable Type And Values    ${resp}    201    ServiceSecurity
        ${resource_url}=    Check Location Header    ${resp}    ${LOCATION_SECURITY_RESOURCE_REGEX}
    END

    RETURN    ${register_user_info_invoker}    ${register_user_info_provider}    ${service_api_description_published}

Create Security Context Between invoker and provider
    [Arguments]    ${register_user_info_invoker}    ${register_user_info_provider}

    ${discover_response}=    Get Request Capif
    ...    ${DISCOVER_URL}${register_user_info_invoker['api_invoker_id']}&aef-id=${register_user_info_provider['aef_id']}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${register_user_info_invoker['management_cert']}

    Check Response Variable Type And Values    ${discover_response}    200    DiscoveredAPIs

    # create Security Context
    ${request_body}=    Create Service Security From Discover Response
    ...    http://${CAPIF_HOSTNAME}:${CAPIF_HTTP_PORT}/test
    ...    ${discover_response}

    ${resp}=    Put Request Capif
    ...    /capif-security/v1/trustedInvokers/${register_user_info_invoker['api_invoker_id']}
    ...    json=${request_body}
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${register_user_info_invoker['management_cert']}

    Check Response Variable Type And Values    ${resp}    201    ServiceSecurity

Get Number Of Services
    ${resp}=    Get Request Capif
    ...    /helper/getServices
    ...    server=${CAPIF_HTTPS_URL}
    ...    verify=ca.crt
    ...    username=${SUPERADMIN_USERNAME}

    Log Dictionary    ${resp.json()}
    ${size}=    Get Length    ${resp.json()['services']}

    RETURN    ${size}
