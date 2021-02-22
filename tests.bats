#!/usr/bin/env bats

# initial setup (only required once)
if [[ "$CREATE_NATIVE_IMAGE" == "1" ]]; then
    ./create_native_image.sh >&2 
fi

function setup {
    export NAMESPACE="test-namespace-$RANDOM"
    export NAME="flask"
    export NATIVE_IMAGE="native_flask_restapi_image"
    export IMAGE="flask_restapi_image"
    export SCONE_CAS_ADDR="5-2-0.scone-cas.cf"
    export BINARY="/usr/local/bin/python3"
    export DEVICE=$(./determine_sgx_device)
    export SCONE_HEAP=1G
    export SCONE_STACK=4M
    export SCONE_ALLOW_DLOPEN=2
}

function teardown {
    unset NAMESPACE
    unset NAME
    unset NATIVE_IMAGE
    unset IMAGE
    unset SCONE_CAS_ADDR
    unset BINARY
    unset DEVICE
    unset SCONE_HEAP
    unset SCONE_STACK
    unset SCONE_ALLOW_DLOPEN
    rm -rf ./flask_restapi_image
    rm strace.log || true
    docker-compose down &> /dev/null || true
}

@test "sconify basic python image" {
    export SESSION=$(./sconify_image --namespace=$NAMESPACE --create-namespace --name=$NAME --from=$NATIVE_IMAGE --to=$IMAGE --cas=$SCONE_CAS_ADDR --dir="/home" --dir="/usr/local/lib" --dir="/app" --dir="/usr/lib/python3.7" --dir="/tls" --binary=$BINARY --heap=$SCONE_HEAP --stack=$SCONE_STACK --dlopen=$SCONE_ALLOW_DLOPEN)
    echo $SESSION

    [ "$SESSION" = "$NAMESPACE/flask" ]

    docker-compose up --detach
    
    TIMEOUT=5
    COUNT=0
    while [[ $(docker-compose logs | grep 'Running on https://0.0.0.0:4996/' -q ) -ne 0 ]]; do
        ((COUNT++))
        if [[ $COUNT -eq $TIMEOUT ]]; then
            exit 1
        fi
        sleep 5
    done
}

@test "sconify python image with strace" {
    docker run --init --cap-add=SYS_PTRACE -it --rm $NATIVE_IMAGE timeout 10 sh -c "apk add --no-cache strace ; strace python3 /app/rest_api.py" > strace.log || true

    export SESSION=$(./sconify_image --namespace=$NAMESPACE --create-namespace --name=$NAME --from=$NATIVE_IMAGE --to=$IMAGE --cas=$SCONE_CAS_ADDR --trace=strace.log --binary=$BINARY --heap=$SCONE_HEAP --stack=$SCONE_STACK --dlopen=$SCONE_ALLOW_DLOPEN)
    echo $SESSION

    [ "$SESSION" = "$NAMESPACE/flask" ]

    docker-compose up --detach
    
    TIMEOUT=5
    COUNT=0
    while [[ $(docker-compose logs | grep 'Running on https://0.0.0.0:4996/' -q ) -ne 0 ]]; do
        ((COUNT++))
        if [[ $COUNT -eq $TIMEOUT ]]; then
            exit 1
        fi
        sleep 5
    done
}
