# Copyright 2016-2017 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

*** Settings ***
Documentation  This resource contains any keywords dealing with operations being performed on a Vsphere instance, mostly govc wrappers
Resource  ../resources/Util.robot

*** Keywords ***
Check VCenter
    Log To Console  \nChecking vCenter availability...
    ${rc}  ${output}=  Run And Return Rc And Output  govc about -u=%{TEST_URL}
    Log To Console  ${output}
    Should Be Equal As Integers  ${rc}  0  vCenter %{TEST_URL} seems unavailable
    Should Contain  ${output}  VMware vCenter Server

Get VCenter Thumbprint
    [Tags]  secret
    ${rc}  ${thumbprint}=  Run And Return Rc And Output  openssl s_client -connect %{TEST_URL}:443 </dev/null 2>/dev/null | openssl x509 -fingerprint -noout | cut -d= -f2
    Should Be Equal As Integers  ${rc}  0
    [Return]  ${thumbprint}

Get VCenter GOVC Fingerprint
    [Tags]  secret
    ${rc}  ${fingerprint}=  Run And Return Rc And Output  govc about.cert -k -thumbprint
    Should Be Equal As Integers  ${rc}  0
    [Return]  ${fingerprint}

Set Test VC Variables
    [Tags]  secret
    ${thumbprint}=  Get VCenter Thumbprint
    Set Global Variable  ${TEST_THUMBPRINT}  ${thumbprint}

Check Delete Success
    [Arguments]  ${name}
    ${out}=  Run  govc ls vm
    Log  ${out}
    Should Not Contain  ${out}  ${name}
    ${out}=  Run  govc datastore.ls
    Log  ${out}
    Should Not Contain  ${out}  ${name}
    ${out}=  Run  govc ls host/*/Resources/*
    Log  ${out}
    Should Not Contain  ${out}  ${name}

Run GOVC
    [Arguments]  ${cmd_options}
    ${rc}  ${output}=  Run And Return Rc And Output  govc ${cmd_options}
    Log  ${output}
    Should Be Equal As Integers  ${rc}  0
    [Return]  ${rc}

Get VM Host Name
    [Arguments]  ${vm}
    ${out}=  Run  govc vm.info ${vm}
    ${out}=  Split To Lines  ${out}
    ${host}=  Fetch From Right  @{out}[-1]  ${SPACE}
    [Return]  ${host}

Get VM Host By IP
    [Arguments]  ${vm-ip}
    ${out}=  Run  govc vm.info -vm.ip=${vm-ip}
    ${out}=  Split To Lines  ${out}
    ${host}=  Fetch From Right  @{out}[-1]  ${SPACE}
    [Return]  ${host}

Get PSC Instance
    [Arguments]  ${vc-ip}  ${vc-root-user}  ${vc-root-pwd}
    Open Connection  ${vc-ip}
    Wait Until Keyword Succeeds  10x  5s  Login  ${vc-root-user}  ${vc-root-pwd}

    ${psc}=  Execute Command And Return Output  /usr/lib/vmware-vmafd/bin/vmafd-cli get-ls-location --server-name localhost | awk -F/ '{print $3}'

    Close Connection

    [Return]  ${psc}

Gather All vSphere Logs
    ${hostList}=  Run  govc ls -t HostSystem host/cls | xargs
    Run  govc logs.download ${hostList}

Check No VSAN DOMs In Datastore
    [Arguments]  ${test_datastore}
    ${out}=  Run  govc datastore.vsan.dom.ls -ds ${test_datastore} -l -o
    Should Be Empty  ${out}

    [Return]  ${out}

Copy Disk
    [Arguments]  ${old-datastore}  ${new-datastore}  ${old-disk}  ${new-disk}
    ${output}=  Run command and Return output  govc datastore.cp -ds "${old-datastore}" -ds-target "${new-datastore}" "${old-disk}" "${new-disk}"
    [Return]  ${output}