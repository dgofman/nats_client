# NATS Client

https://nats.io/

NATS is an open-source messaging system (sometimes called message-oriented middleware).
The NATS server is written in the Go programming language.
The NATS client provides communication between client devices such as Android, iPhone, iPad,
Web browsers, and desktop applications with the server using the NATS exchange system.
It supports secure layer protocol using SSL/TLS and [CA certificates](https://github.com/dgofman/nats_client/blob/master/test/tls.sh).



# Initialize Project

flutter create --project-name nats_client -i objc -a java -t app .


## Implementation

- Using NatsLight library (jwt bearer token)
 ```
import 'dart:convert';

import 'package:nats_client/natslite/nats.dart';
import 'package:nats_client/natslite/subscription.dart';

...
  final conn = await Nats.connect(
      opts: { 'servers': server, 'token': token},
      debug: true,
      statusCallback: (status, error) {
        print('$status (${error.toString()})');
      });
  conn.subscribe('chat', (Result result) {
    print(result.data);
  });
  conn.publish('enter', utf8.encode(json.encode({'id': myId})));
```

```
import 'package:nats_client/natslite/nats.dart';
import 'package:nats_client/natslite/constants.dart';
import 'package:nats_client/natslite/subscription.dart';

...
    const token = 'CREATE USER TOKEN - nsc add user --bearer --name <n>';
    late Nats conn;
    conn = Nats(opts: {}, debug: true,
        statusCallback: (status, error) async {
          if (error != null) {
            print('NetService:ERROR $error');
          }
          if (status == Status.PING_TIMER) {
            print(status.toString());
          } else if (status == Status.CONNECT) {
            // sync request
            final msg = await conn.request('/test/notifications', utf8.encode(json.encode({})););
            print(json.decode(utf8.decode(msg)));
            
            // subscribe to channel
            conn.subscribe('/test/notifications/stream', (Result res) {
              print(utf8.decode(res.data));
            });
          }
        });
    conn.authenticator.auth = (String nonce) {
      return {'jwt': token, 'nkey': '', 'sig': ''};
    };
    conn.init('wss://{{SERVER}}');
  }
```



## Using Nats Authenticators
[Demo](https://github.com/dgofman/nats_client/blob/master/test/demo.dart)

[JwtAuthenticator](https://github.com/dgofman/nats_client/blob/master/test/setup.sh#L41)
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/jwtauth.dart';
  ...
  final conn = await Nats.connect(
      opts: { 'servers': server },
      authenticator: JwtAuthenticator(token),
     ...
```

[UserAuthenticator](https://github.com/dgofman/nats_client/blob/master/test/setup.sh#L14)
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/userauth.dart';
  ...
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: UserAuthenticator(login_auth_token),
     ...
```

[UserAuthenticator](https://github.com/dgofman/nats_client/blob/master/test/setup.sh#L66)
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/userauth.dart';
  ...
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: UserAuthenticator(username, password),
     ...
```

[NKeyAuthenticator](https://github.com/dgofman/nats_client/blob/master/test/setup.sh#L149)
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/userauth.dart';
  ...
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: NKeyAuthenticator('SUAOMTSAOJJNB5TIPMYC5W2OMXDS6ST3Z3PDLDJHCMTGV7SKWVPDL2OU3Y'),
     ...
```

[CredsAuthenticator](https://github.com/dgofman/nats_client/blob/master/test/setup.sh#L199)
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/credauth.dart';
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: CredsAuthenticator(certificate),
     ...
```

## Installation of the NGS and NSC utilities
https://downloads.synadia.com/ngs/signup

- NGS depends on two command line tools. The first, called nsc, is an open source tool used to create and edit configurations for the NATS.io account security system. This is the same system used by NGS. The second, called ngs, is used to manage your billing account with Synadia.
  The installation process is straightforward. Open up a command prompt and type the following:
```
$ curl https://downloads.synadia.com/ngs/install.py -sSf | python
```

- This will install the nsc and ngs utilities into ~/.nsc/bin. You can get usage help anytime by executing ngs -h or nsc -h, or search the nsc documentation.
  Next we need to tell NSC about Synadia, create an account and user and deploy the account to the NGS servers. To create a new account named "First" (you can use any name here) and deploy it to NGS, open a command prompt and type:
```
$ nsc init -o synadia -n First
```

- Verify generated env, jwt, account, user and keys
```
nsc env

nsc describe jwt  -f ~/.local/share/nats/nsc/stores/synadia/synadia.jwt

nsc describe account    or    nsc list accounts

nsc describe user    or    nsc list users

tree ~/.local/share/nats/nsc/keys/keys    or    nsc list keys 
        (Where Account Key: nsc list keys -a)
        (Where User Key: nsc list keys -u)

 
ngs status -d ~/.local/share/nats/nsc/stores/synadia
 > Other... (ENTER)
 path to signer account nkey or nkey  ~/.local/share/nats/nsc/keys/keys/A/{KEY_DIR}/KEY_NAME.nk
```

- Switch to Developer Plan
```
ngs edit -d ~/.local/share/nats/nsc/stores/synadia/
 > Other... (ENTER)
 path to signer account nkey or nkey  ~/.local/share/nats/nsc/keys/keys/A/{KEY_DIR}/KEY_NAME.nk
 > Developer $0.00/month
 ? Email
 > OK
```

## Installation NATS Server
https://nats.io/download/

- Create the Server Config
```
nsc generate config --mem-resolver --config-file {DIR_PATH}/nsc-server.conf 
```

- Start server
```
nats-server -c {DIR_PATH}/nsc-server.conf 
```