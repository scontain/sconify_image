# Sconifying an existing Container Image (Community Version)

To integrate with existing container image pipelines, we support the encryption of existing images. In this example, we

- first, generate a *native image* that contains a Flask-based application: this image is the result of an existing image generation pipeline

- second, we **sconify** this native image, i.e., we 

  - generate an **encrypted image** in which all Python code and dependencies are encrypted. Note that is required for both integrity as well as confidentiality of the code.
  - generate a SCONE security policy that ensures that only our application can read the code in clear text

This second step uses a SCONE community version of Python. For the commercial version, we support to convert a binary into a binary that runs inside of an SGX enclave. 

!!!note "Community Version is not intended for production"
	   To run the sconified binary in production, it must be signed using our `scone-signer` utility. Only signed binaries can be considered sufficiently secure.

### Stage One: Native Image Generation

We generate our native image with the help of a Dockerfile by executing:

```bash
./create_native_image.sh
```

You could try out this image by running

```bash
docker-compose --file native-docker-compose.yml up
```

You can now submit requests as follows:

```bash
export URL=https://api:4996
 curl -k -X POST ${URL}/patient/patient_3 -d "fname=Jane&lname=Doe&address='123 Main Street'&city=Richmond&state=Washington&ssn=123-223-2345&email=nr@aaa.com&dob=01/01/2010&contactphone=123-234-3456&drugallergies='Sulpha, Penicillin, Tree Nut'&preexistingconditions='diabetes, hypertension, asthma'&dateadmitted=01/05/2010&insurancedetails='Primera Blue Cross'" --resolve api:4996:127.0.0.1
curl -k -X GET ${URL}/patient/patient_3 --resolve api:4996:127.0.0.1
```

## Stage Two: Encrypted Image

We now transform the native image that we generated in stage one, into a new encrypted image in which the application runs inside of an SGX enclave.

### Determine directories that we need to encrypt

One can use a dynamic analyis approach to determine which directories are accessed by the application:

```bash
docker run --init --cap-add=SYS_PTRACE -it --rm  native_flask_restapi_image  timeout  30 sh -c "apk add --no-cache strace ; strace python3 /app/rest_api.py" > strace.log
```

One can see that the application access the following directories:

 - `/usr/local/lib`
 - `/app`
 - `/usr/loca/lib/python3.7`
 - `/tls`

### Security Policy

We provide a default security policy template (see file `session-template.yml`). In this example, we need to provide the application, i.e., flask, with a certificate and a private key. We added two `hooks` in the default policy to 1) define secrets in the policy, and 2) *inject* these files in the filesystem of the application, i.e., they are only visible to the application after successfully attesting the application.

We define for our application  a TLS certificate (`flask`) and a private key (`flask_key`). Note that we specify a **DNS** name `api`, i.e., clients need to access this service as `https://api`. To generate
a certificate, we require a CA (Certification Authority). Hence, we generate a CA (`api_ca_cert`) and the private key of the CA (`api_ca_key`). 

```bash
export SECRETS=$(cat <<EOF
secrets:
    - name: api_ca_key
      kind: private-key
    - name: api_ca_cert
      kind: x509-ca
      export_public: true
      private_key: api_ca_key
    - name: flask_key
      kind: private-key
    - name: flask
      kind: x509
      private_key: flask_key
      issuer: api_ca_cert
      dns:
        - api
EOF
)
```

The certificate and the private key need to be made available to the program - which expects
these at paths `/tls/flask.crt` and `/tls/flask.key`, respectively. Hence, 
we inject these secrets into files:

```bash
export INJECTED_FILES=$(cat <<EOF
     injection_files:
        - path: "/tls/flask.crt"
          content: \$\$SCONE::flask.crt\$\$
        - path: "/tls/flask.key"
          content: "\$\$SCONE::flask.key\$\$"
EOF
)
```

### Generate the encrypted image

We define some environment variables to sconify the image

- The name of the container image that was created by `./create_native_image.sh`:

```bash
export NATIVE_IMAGE="native_flask_restapi_image"
```

- The name of the generated encrypted container image:

```bash
export IMAGE="flask_restapi_image"
```

- We use a public SCONE CAS to store the session policies

```bash
export SCONE_CAS_ADDR="5-2-0.scone-cas.cf"
```

- we define a random namespace for this policy:

```bash
export NAMESPACE="my_namespace-$RANDOM"
```

- we define the binary that needs to be sconified:

```bash
export BINARY="/usr/local/bin/python3"
```

- we define the [SCONE environment variables]("https://sconedocs.github.io/SCONE_ENV/") to configure the secure execution:

```bash
export SCONE_HEAP=1G
export SCONE_STACK=4M
export SCONE_ALLOW_DLOPEN=2
```

Now, we can create the encrypted image, instantiate policy template and upload the policy in one step:

```bash
export SESSION=$(./sconify_image --namespace=$NAMESPACE --name=flask --from=$NATIVE_IMAGE --to=$IMAGE --cas=$SCONE_CAS_ADDR --dir="/home" --dir="/usr/local/lib" --dir="/app" --dir="/usr/lib/python3.7" --dir="/tls" --heap=$SCONE_HEAP --stack=$SCONE_STACK --dlopen=$SCONE_ALLOW_DLOPEN  --binary=$BINARY)
```

Environment variable SESSION will contain the name of the session, which in this case would be "$NAMESPACE-flask" because we set the name of the session to be `flask` (i.e., by passing argument `--name=flask`).

The community version of `sconify_image` requires the specification of a `--base` image that contains the sconified binary. The commercial version can also `sconify` the binary, i.e., convert it such that it can run automagically inside of SGX enclaves.

### STEP 3: Execute Image

We show how to run this locally by executing. We first determine the SGX device name of the local computer:

```bash
export DEVICE=$(./determine_sgx_device)
```

and then we run the encrypted image using `docker-compose`:

```bash
docker-compose up
```
