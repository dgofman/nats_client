# NATS Client

https://nats.io/

NATS is an open-source messaging system (sometimes called message-oriented middleware). 
The NATS server is written in the Go programming language. 
Client libraries to interface with the server are available for dozens of major programming languages. 
The core design principles of NATS are performance, scalability, and ease of use.

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



 - Using Nats Authenticators
 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/jwtauth.dart';
  ...
  final conn = await Nats.connect(
      opts: { 'servers': server },
      authenticator: JwtAuthenticator.create(token),
     ...
```

 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/userauth.dart';
  ...
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: UserAuthenticator.create(username, password),
     ...
```

 ```
  import 'package:nats_client/natslite/nats.dart';
  import 'package:nats_client/nats/credauth.dart';
  final conn = await Nats.connect(
     opts: { 'servers': server },
     authenticator: CredsAuthenticator.create(certificate),
     ...
```
