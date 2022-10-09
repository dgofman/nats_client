#!/bin/sh

cat > token.conf <<- EOF
# https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro/tokens
#
# Start the server
# nats-server -c token.conf
# or
# nats-server -c exisitng_server.conf --auth login_auth_token
#
# nats_client - Flutter Library
#
# import 'package:nats_client/nats/userauth.dart';
# authenticator = UserAuthenticator('login_auth_token');
#

port: 4222

authorization: {
  token: login_auth_token
}

websocket {
  port: 8443
  no_tls: true
}
EOF

export TEST_CRED_JWT_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTE5LW5rZXkifQ.eyJqdGkiOiJNN0xKTUdOVkZNNEhaMkFJSEhPRTdFT1JJUk03UVFMRVBVU0E1RUlUUzVGNkczNFpJQVlRIiwiaWF0IjoxNjY1MDI2MjkzLCJpc3MiOiJPQ1pNWVhOM1ZESVNYSlBFWFdaUUNCSlBFRDRRVTRVSFIzVENUQUk1SFBWQkFRNU1JSkdYRzZTWSIsIm5hbWUiOiJDTElFTlRfQSIsInN1YiI6IkFCUUdKSURCRlc0TkdaT1o0NlFXWTdZU0pPRlJWUE5FN08yUUIyNzY3RFZRVEdIRVE0N0dXNU1RIiwibmF0cyI6eyJsaW1pdHMiOnsic3VicyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwiaW1wb3J0cyI6LTEsImV4cG9ydHMiOi0xLCJ3aWxkY2FyZHMiOnRydWUsImNvbm4iOi0xLCJsZWFmIjotMX0sImRlZmF1bHRfcGVybWlzc2lvbnMiOnsicHViIjp7fSwic3ViIjp7fX0sInR5cGUiOiJhY2NvdW50IiwidmVyc2lvbiI6Mn19.TMTnV3FbCgSWox7y0Jr3ozzmbDXwUXkUxv5yUF9k51R1S7FrPS9ZwSLedGAGsvgyu8nVe-CDNfrVz6AhLAXsDw

cat > jwt.conf <<- EOF
# https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro/jwt
#
# Start the server
# nats-server -c jwt.conf
#
# nats_client - Flutter Library
#
# // JwtAuthenticator('-----BEGIN NATS USER JWT-----', '-----BEGIN USER NKEY SEED-----')
# import 'package:nats_client/nats/jwtauth.dart';
# final authenticator = JwtAuthenticator('$TEST_CRED_JWT_TOKEN', 'SUAGB2ERP7PPAYHKSS7PBURMGLFNWZLM6DVJSWVYWGICE7SZ56VO3OKIBU');
#

port: 4222

resolver: MEMORY
resolver_preload: {
  ACCOUNT-JWT_PASTE-HERE: $TEST_CRED_JWT_TOKEN
}

websocket {
  port: 8443
  no_tls: true
}
EOF

cat > user_plain_pwd.conf <<- EOF
# https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro/username_password
#
# Start the server
# nats-server -c user_plain_pwd.conf
#
# nats_client - Flutter Library
#
# import 'package:nats_client/nats/userauth.dart';
# final authenticator = UserAuthenticator('username', 'mypassword');
#

port: 4222

authorization: {
  users = [
    {
      user: username
      password: mypassword
      permissions: {
        publish: {
          deny: ">"
        },
        subscribe: {
          allow: "user.>"
        }
      }
    }
  ]
}

websocket {
  port: 8443
  no_tls: true
}
EOF

export PASSWORD="01234-56789-98765-43210"

cat > user_bcrypt_pwd.conf <<- EOF
# https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro/username_password#bcrypted-passwords
#
# Generated password using bcrypt (password should be at least 22 characters long)
# nats server pass -p '$PASSWORD'
#
# Start the server
# nats-server -c user_bcrypt_pwd.conf
#
# nats_client - Flutter Library
#
# import 'package:nats_client/nats/userauth.dart';
# final authenticator = UserAuthenticator('username', '$PASSWORD');
#

port: 4222

authorization: {
  users = [
    {
      user: username
      password: \$2a\$11\$ODAlEG0fPKHj21WhkrbzqOhUWYyT3IDoNXsAeVJYJ3fFUf8xQRM.6
      permissions: {
        publish: {
          allow: "user.>"
        },
        subscribe: {
          allow: "user.>"
        }
      }
    }
  ]
}

websocket {
  port: 8443
  no_tls: true
}
EOF

cat > user_nkey_pwd.conf <<- EOF
# https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro/nkey_auth
#
# Generated password using nkey  (seed + user)
# go install github.com/nats-io/nkeys/nk@latest
# nk -gen user -pubout
#
# Start the server
# nats-server -c user_nkey_pwd.conf
#
# nats_client - Flutter Library
#
# import 'package:nats_client/nats/nkeyauth.dart';
# final authenticator = NKeyAuthenticator('SUAOMTSAOJJNB5TIPMYC5W2OMXDS6ST3Z3PDLDJHCMTGV7SKWVPDL2OU3Y'); //SEED
#

port: 4222

authorization: {
  users = [
    {
      nkey: UBNNMTD3BFCIURAEJBRFZUJ3P5MOGGDLESOV3FKCZCP4O4HK7PBKBNTZ
      permissions: {
        publish: ">"
        subscribe: ">"
      }
    }
  ]
}

websocket {
  port: 8443
  no_tls: true
}
EOF