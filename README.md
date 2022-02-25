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
