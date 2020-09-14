# A simple flask example executed inside of an SGX enclave

## Setup

```bash
git clone https://github.com/scontain/flask_example.git
cd flask_example
```


## Run Service using docker-compose

```bash
./create_image.sh
source myenv
docker-compose up
```

### Testing the service

Retrieve the API certificate from CAS:

```bash
source myenv
curl -k -X GET "https://${SCONE_CAS_ADDR-cas}:8081/v1/values/session=$FLASK_SESSION" | jq -r .values.api_ca_cert.value > cacert.pem
```

Since the API certificates are issued to the host name "api", we have to use it. You can rely on cURL's --resolve option to point to the actual address (you can also edit your /etc/hosts file).

```bash
export URL=https://api:4996
```

```bash
curl --cacert cacert.pem -X POST ${URL}/patient/patient_3 -d "fname=Jane&lname=Doe&address='123 Main Street'&city=Richmond&state=Washington&ssn=123-223-2345&email=nr@aaa.com&dob=01/01/2010&contactphone=123-234-3456&drugallergies='Sulpha, Penicillin, Tree Nut'&preexistingconditions='diabetes, hypertension, asthma'&dateadmitted=01/05/2010&insurancedetails='Primera Blue Cross'" --resolve api:4996:127.0.0.1
curl --cacert cacert.pem -X GET ${URL}/patient/patient_3 --resolve api:4996:127.0.0.1
curl --cacert cacert.pem -X GET ${URL}/score/patient_3 --resolve api:4996:127.0.0.1
```

The output might look as follows:

```txt
$ curl --cacert cacert.pem -X POST https://localhost:4996/patient/patient_3 -d "fname=Jane&lname=Doe&address='123 Main Street'&city=Richmond&state=Washington&ssn=123-223-2345&email=nr@aaa.com&dob=01/01/2010&contactphone=123-234-3456&drugallergies='Sulpha, Penicillin, Tree Nut'&preexistingconditions='diabetes, hypertension, asthma'&dateadmitted=01/05/2010&insurancedetails='Primera Blue Cross'" --resolve api:4996:127.0.0.1
{"address":"'123 Main Street'","city":"Richmond","contactphone":"123-234-3456","dateadmitted":"01/05/2010","dob":"01/01/2010","drugallergies":"'Sulpha, Penicillin, Tree Nut'","email":"nr@aaa.com","fname":"Jane","id":"patient_3","insurancedetails":"'Primera Blue Cross'","lname":"Doe","preexistingconditions":"'diabetes, hypertension, asthma'","score":0.1168424489618366,"ssn":"123-223-2345","state":"Washington"}
$ curl --cacert cacert.pem -X GET localhost:4996/patient/patient_3 --resolve api:4996:127.0.0.1
{"address":"'123 Main Street'","city":"Richmond","contactphone":"123-234-3456","dateadmitted":"01/05/2010","dob":"01/01/2010","drugallergies":"'Sulpha, Penicillin, Tree Nut'","email":"nr@aaa.com","fname":"Jane","id":"patient_3","insurancedetails":"'Primera Blue Cross'","lname":"Doe","preexistingconditions":"'diabetes, hypertension, asthma'","score":0.1168424489618366,"ssn":"123-223-2345","state":"Washington"}
$ curl --cacert cacert.pem -X GET localhost:4996/score/patient_3 --resolve api:4996:127.0.0.1
{"id":"patient_3","score":0.2781606437899131}
```

## Execution on a Kubernetes Cluster

### Install SCONE services

Get access to `SconeApps` (see <https://sconedocs.github.io/helm/>):

```bash
helm repo add sconeapps https://${GH_TOKEN}@raw.githubusercontent.com/scontain/sconeapps/master/
helm repo update
```

Give SconeApps access to the private docker images (see <https://sconedocs.github.io/helm/>)

```bash
export DOCKER_HUB_USERNAME=...
export DOCKER_HUB_ACCESS_TOKEN=...
export DOCKER_HUB_EMAIL=...

kubectl create secret docker-registry sconeapps --docker-server=index.docker.io/v1/ --docker-username=$DOCKER_HUB_USERNAME --docker-password=$DOCKER_HUB_ACCESS_TOKEN --docker-email=$DOCKER_HUB_EMAIL
```

Start LAS and CAS service:

```bash
helm install las sconeapps/las --set service.hostPort=true
helm install cas sconeapps/cas
```

Install the SGX device plugin for Kubernetes:

```bash
helm install sgxdevplugin sconeapps/sgxdevplugin
```

### Run the application

Start by creating a Docker image and setting its name. Remember to specify a repository to which you are allowed to push:

```bash
export IMAGE=sconecuratedimages/application:v0.4
./create_image.sh
source myenv
docker push $IMAGE
```

Use the Helm chart in `deploy/helm` to deploy the application to a Kubernetes cluster.

```bash
helm install api-v1 deploy/helm \
   --set image=$IMAGE \
   --set scone.cas=$SCONE_CAS_ADDR \
   --set scone.flask_session=$FLASK_SESSION/flask_restapi \
   --set scone.redis_session=$REDIS_SESSION/redis \
   --set service.type=LoadBalancer
```

**NOTE**: Setting `service.type=LoadBalancer` will allow the application to get traffic from the internet (through a managed LoadBalancer).

### Test the application

After all resources are `Running`, you can test the API via Helm:

```bash
helm test api-v1
```

Helm will run a pod with a couple of pre-set queries to check if the API is working properly.

### Access the application

If the application is exposed to the world through a service of type LoadBalancer, you can retrieve its CA certificate from CAS:

```bash
source myenv
curl -k -X GET "https://${SCONE_CAS_ADDR-cas}:8081/v1/values/session=$FLASK_SESSION" | jq -r .values.api_ca_cert.value > cacert.pem
```

Retrieve the service public IP address:

```bash
export SERVICE_IP=$(kubectl get svc --namespace default api-v1-example --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}")
```

Since the API certificates are issued to the host name "api", we have to use it. You can rely on cURL's --resolve option to point to the actual address (you can also edit your /etc/hosts file).

```bash
export URL=https://api
```

Now you can perform queries such as:

```bash
curl --cacert cacert.pem -X POST ${URL}/patient/patient_3 -d "fname=Jane&lname=Doe&address='123 Main Street'&city=Richmond&state=Washington&ssn=123-223-2345&email=nr@aaa.com&dob=01/01/2010&contactphone=123-234-3456&drugallergies='Sulpha, Penicillin, Tree Nut'&preexistingconditions='diabetes, hypertension, asthma'&dateadmitted=01/05/2010&insurancedetails='Primera Blue Cross'" --resolve api:443:${SERVICE_IP}
```

### Clean up

```bash
helm delete cas
helm delete las
helm delete sgxdevplugin
helm delete api-v1
kubectl delete pod api-v1-example-test-api
```

## Pipelined Image Generation

To integrate with existing container image pipelines, we support a pipelined image generation. In this example, we

- first, generate a *native image* that contains our Flask-based application
- second, we use this native image and
  - generate an *encrypted image* in which all Python code and dependencies are encrypted. Note that is required for both integrity as well as confidentiality of the code.
  - generate a SCONE security policy that ensure that only our Flask-based application can read the code in clear text
- third, we replace the Redis image by a SCONE-based Redis image

### Stage One: Native Image Generation

We generate our code with a simple Dockerfile by executing:

```bash
./create_native_image.sh
```

You could - im principle - try out this image by running

```bash
docker-compose --file native-docker-compose.yml up
```

However, this will block since REDIS does not support TLS yet. We would need some more steps to set up a working TLS connection to REDIS. Instead of trying to set up all the certificates manually, lets's try to create
an encrypted image and solve the distribution of the TLS certificates using SCONE CAS.

### Stage Two: Encrypted Image

We now transform the native image that we generated in stage one, into a new encrypted image in which the Flask-based application runs inside of an SGX enclave.

For that we have defined two policy templates that generate the TLS certificates and share the TLS certificates between REDIS and FLASK.
The two policies ensure that REDIS attests the Flask App and that the Flask app attests REDIS implicitly via TLS.

```bash
export NATIVE_IMAGE="native_flask_restapi_image"  # image that was created by ./create_native_image.sh
export IMAGE="flask_restapi_image" # the name of the encrypted Python image
export SCONE_CAS_ADDR="4-0-0.scone-cas.cf" # we use a public SCONE CAS to store the session policies
export FLASK_SESSION="FLASK_SESSION-$RANDOM-$RANDOM-$RANDOM"
unset REDIS_SESSION
export REDIS_SESSION=$(./upload_session --template=redis-template.yml --session=redis_session.yml  --image=sconecuratedimages/experimental:redis-6-ubuntu --cas=$SCONE_CAS_ADDR)
export DEVICE=$(./determine_sgx_device) # determine the SGX device of the local computer
./sconify_image --from=$NATIVE_IMAGE --to=$IMAGE --template=flask-sconify-template.yml --session=flask_session.yml --cas=$SCONE_CAS_ADDR # create encrypted image, instantiate policy template and upload policy
```

and then run locally by executing

```bash
docker-compose up
```

The next step is to run REDIS and the Flask app using the helm charts (as described above).
