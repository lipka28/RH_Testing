#!/bin/bash

# This script was only tested on Fedora 33
# Tests are donew with tls1.2 where available (tls1.3 defaults to specific cypher look into testplan.txt for details)

OP_SSL_PACKAGE=openssl

#---------------------------------------Helper functions------------------------------------#
check_privilages(){
    if [ "$EUID" -ne 0 ]
        then echo "Please run this script as root"
        exit
    fi
}

start_server(){
    #Start server in the background and redirect STDOUT and STDER to /dev/null
    #Later test fail to connet to server when -www not specified
    openssl s_server -key key.pem -cert server.pem -accept 44330 -www > /dev/null 2>&1 &
    
    #Wait for server to startup
    sleep 1
}

kill_server(){
    #Kill server process
    pkill openssl
}

setup(){    
    #check if run with root privilages
    check_privilages
    
    clear
    echo "Setting up the enviroment..."
    
    #Install openssl package
    dnf -y -q install $OP_SSL_PACKAGE
    
    #Detect system crypto-policy
    DEFAULT_POLICY=$(update-crypto-policies --show)
    
    #Generate Key and Cert
    openssl req -x509 -newkey rsa -keyout key.pem \
    -out server.pem -days 365 -nodes -subj "/CN=localhost" > /dev/null 2>&1
    
    echo "Done!"
}

set_crypto_policy_to_DEFAULT(){
    update-crypto-policies --set DEFAULT > /dev/null
}

set_crypto_policy_to_LEGACY(){
    update-crypto-policies --set LEGACY > /dev/null
}

reset_crypto_policy(){
    update-crypto-policies --set $DEFAULT_POLICY > /dev/null
}

run_tests(){
    TEST_SUCC=0
    EXPECTED_SUCC=3

    TEST_LEGACY_TLS
    TEST_LEGACY_CAMELLIA
    TEST_DEFAULT_SUPPORTED_TLS
    
    echo ""
    echo "Test Resutls:"
    echo "$TEST_SUCC out of $EXPECTED_SUCC Successful test"
    echo "$((EXPECTED_SUCC-TEST_SUCC)) Failures"
}

cleanup(){
    echo "Cleaing up the Enviroment..."
   
    #Remove openssl package
    dnf -y -q remove $OP_SSL_PACKAGE 
    dnf -y -q autoremove
    
    #Remove Key and Certificate
    rm *.pem
    
    #Return system crpyto-policy to previous state
    reset_crypto_policy
   
    echo "Done!"
}

#---------------------------------------Helper functions------------------------------------#


#--------------------------------------Testing functions------------------------------------#
TEST_LEGACY_TLS(){
    #Expected test result
    local expected_result=4
    local result=0
	
    echo "TEST_LEGACY_TLS....."
    #Set crypto-policy and start server
    set_crypto_policy_to_LEGACY
    start_server
    for tls_ver in tls1 tls1_1 tls1_2 tls1_3; do
        openssl s_client -connect localhost:44330 -$tls_ver < /dev/null > /dev/null 2>&1 && ((++result))
    done

    if [ $result -eq $expected_result ]
    then 
        echo "OK"
        ((++TEST_SUCC))
    else echo "FAIL"
    fi
    
    kill_server
}
TEST_LEGACY_CAMELLIA(){
    #Expected test result
    local expected_result=0
    local result=0
    local skip=0
	
    echo "TEST_LEGACY_CAMELLIA....."
    #Set crypto-policy and start server
    set_crypto_policy_to_LEGACY
    start_server
    for ciph in $(openssl ciphers CAMELLIA | tr ':' ' '); do
        # dirty fix for bug? in openssl ciphers
        if [ $skip -lt 4 ] 
            then 
            ((++skip))
            continue
        fi
        openssl s_client -connect localhost:44330 -tls1_2 \
        -cipher $ciph < /dev/null > /dev/null 2>&1 && ((++result))
    done

    if [ $result -eq $expected_result ]
    then 
        echo "OK"
        ((++TEST_SUCC))
    else echo "FAIL"
    fi
    
    kill_server
}
TEST_DEFAULT_SUPPORTED_TLS(){
    #Expected test result
    local expected_result=2
    local result=0
	
    echo "TEST_DEFAULT_SUPPORTED_TLS....."
    #Set crypto-policy and start server
    set_crypto_policy_to_DEFAULT
    start_server
    for tls_ver in tls1_2 tls1_3; do
        openssl s_client -connect localhost:44330 -$tls_ver < /dev/null > /dev/null 2>&1 && ((++result))
    done

    if [ $result -eq $expected_result ]
    then 
        echo "OK"
        ((++TEST_SUCC))
    else echo "FAIL"
    fi
    
    kill_server
}

#--------------------------------------Testing functions------------------------------------#


#-----------------------------------------Program body--------------------------------------#
setup
run_tests
cleanup
#-----------------------------------------Program body--------------------------------------#
