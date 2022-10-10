#!/bin/sh

useIntermediate=true

export CERT_HOME=$HOME/.cert

export rootCA_CN="Example CA Root Certificate"
export intermediateCA_CN="Example CA Intermediate Certificate"
export server_CN="Example Server Certificate"
export client_CN="Example Client Certificate"

export expiry=365000h
export NKEY_CREDS="$HOME/.nsc/nats/nsc/nkeys/creds"
export NKEY_OPERATOR="*"  # * - find first operator
export NKEY_USER="*"      # * - find first account
export CERT_PASSWORD=PASSWORD # password for p12 certificate

# It is recommended to hardcode the external IP address
export ROUTE_IP=`ip route get 8.8.8.8 | awk '{print $NF; exit}'`

export HOSTS=`cat << EOF
  "hosts": [
    "www.example.com",
    "example.us",
    "*.example.us",
    "https://www.example.us",
    "localhost",
    "$ROUTE_IP"
  ]
EOF
`
export SUBJECT=`cat << EOF
  "names": [
      {
          "C":  "US",
          "ST": "UT",
          "L":  "Pleasant Grove",
          "O":  "Example Inc.",
          "OU": "OU=Example Unit"
      }
  ]
EOF
`

mkdir -p $CERT_HOME
echo $CERT_HOME

# rootCA certificate file
cat > $CERT_HOME/rootCA.json <<- EOF
{
  "CN": "$rootCA_CN",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "ca": {
    "expiry": "$expiry",
    "pathlen": 2
  },
$SUBJECT
}
EOF

# generate root CA certificate
cfssl genkey -initca $CERT_HOME/rootCA.json | cfssljson -bare $CERT_HOME/rootCA

# inspect
openssl x509 -in $CERT_HOME/rootCA.pem -text -noout | grep Subject:

# CA config file
cat > $CERT_HOME/ca-config.json <<- EOF
{
    "signing": {
        "default": {
            "expiry": "$expiry",
            "usages": [
                "digital signature",
                "cert sign",
                "crl sign",
                "signing"
            ],
            "ca_constraint": {
                "is_ca": true,
                "max_path_len": 0,
                "max_path_len_zero": true
            }
        },
        "profiles": {
            "intermediate": {
                "expiry": "$expiry",
                "usages": [
                    "signing",
                    "key encipherment",
                    "cert sign",
                    "crl sign"
                ],
                "ca_constraint": {
                    "is_ca": true,
                    "max_path_len": 1
                }
            },
            "server": {
                "expiry": "$expiry",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "cert sign",
                    "crl sign"
                ]
            },
            "client": {
                "expiry": "$expiry",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth",
                    "email protection"
                ]
            }
        }
    }
}
EOF

if [ "$useIntermediate" = true ] ; then
# intermediate CA certificate file
cat > $CERT_HOME/intermediateCA.json <<- EOF
{
  "CN": "$intermediateCA_CN",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
$HOSTS,
$SUBJECT
}
EOF

# generate intermediate CA certificate
cfssl gencert -ca $CERT_HOME/rootCA.pem -ca-key $CERT_HOME/rootCA-key.pem -config $CERT_HOME/ca-config.json -profile=intermediate $CERT_HOME/intermediateCA.json | cfssljson -bare $CERT_HOME/intermediateCA

# inspect
openssl x509 -in $CERT_HOME/intermediateCA.pem -text -noout | grep Subject:
fi

# server certificate file
cat > $CERT_HOME/server.json <<- EOF
{
  "CN": "$server_CN",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
$HOSTS,
$SUBJECT
}
EOF

# generate server certificate
if [ "$useIntermediate" = true ] ; then
  cfssl gencert -ca $CERT_HOME/intermediateCA.pem -ca-key $CERT_HOME/intermediateCA-key.pem -config $CERT_HOME/ca-config.json -profile=server $CERT_HOME/server.json | cfssljson -bare $CERT_HOME/server
  cat $CERT_HOME/rootCA.pem $CERT_HOME/intermediateCA.pem > $CERT_HOME/chainCA.pem
else
  cfssl gencert -ca $CERT_HOME/rootCA.pem -ca-key $CERT_HOME/rootCA-key.pem -config $CERT_HOME/ca-config.json -profile=server $CERT_HOME/server.json | cfssljson -bare $CERT_HOME/server
  cat $CERT_HOME/rootCA.pem > $CERT_HOME/chainCA.pem
fi

# inspect
openssl x509 -in $CERT_HOME/server.pem -text -noout | grep Subject:

# verify a server certificate
openssl verify -CAfile $CERT_HOME/chainCA.pem $CERT_HOME/server.pem

# client certificate file
cat > $CERT_HOME/client.json <<- EOF
{
  "CN": "$client_CN",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
$HOSTS,
$SUBJECT
}
EOF

# generate client certificate
if [ "$useIntermediate" = true ] ; then
  cfssl gencert -ca $CERT_HOME/intermediateCA.pem -ca-key $CERT_HOME/intermediateCA-key.pem -config $CERT_HOME/ca-config.json -profile=client $CERT_HOME/client.json | cfssljson -bare $CERT_HOME/client
else
  cfssl gencert -ca $CERT_HOME/rootCA.pem -ca-key $CERT_HOME/rootCA-key.pem -config $CERT_HOME/ca-config.json -profile=client $CERT_HOME/client.json | cfssljson -bare $CERT_HOME/client
fi

# inspect
openssl x509 -in $CERT_HOME/client.pem -text -noout | grep Subject:

# verify a client certificate
openssl verify -CAfile $CERT_HOME/chainCA.pem $CERT_HOME/client.pem


# Generate the Client pkcs12 Certificate
openssl pkcs12 -in $CERT_HOME/server.pem -nokeys -passout pass:$CERT_PASSWORD -export -out $CERT_HOME/cert.p12

# cleanup
rm -f $CERT_HOME/*.json $CERT_HOME/*.csr $CERT_HOME/chainCA.pem

# rename
mv $CERT_HOME/server.pem $CERT_HOME/server-cert.pem
mv $CERT_HOME/client.pem $CERT_HOME/client-cert.pem

export certCA="$CERT_HOME/rootCA.pem"
export NKEY_USER_FILE=`ls $NKEY_CREDS/$NKEY_OPERATOR/$NKEY_USER/$NKEY_USER.creds | head -n 1`
echo $NKEY_USER_FILE
echo "GO Code"
export USER_JWT=`cat $NKEY_USER_FILE | grep "BEGIN NATS USER JWT" -A1 | awk '{getline; print}'`
export USER_SEED=`cat $NKEY_USER_FILE | grep "BEGIN USER NKEY SEED" -A1 | awk '{getline; print}'`

if [ "$useIntermediate" = true ] ; then
  certCA="$CERT_HOME/intermediateCA.pem"
fi
cat <<EOF
    nc, err := nats.Connect("wss://$ROUTE_IP:8443",
        nats.ClientCert("$CERT_HOME/client-cert.pem", "$CERT_HOME/client-key.pem"),
        nats.RootCAs("$certCA"),
        nats.UserJWTAndSeed(
            "$USER_JWT",
            "$USER_SEED"),
    )
EOF

# Move rootCA-key.pem and (intermediateCA-key.pem) private key(s), and keep it in a safe, offline place.