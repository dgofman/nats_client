import 'dart:developer';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:nats_client/natslite/constants.dart';
import 'package:nats_client/natslite/nats.dart';
import 'package:nats_client/natslite/subscription.dart';

import 'package:nats_client/nats/tls.dart';
import 'package:nats_client/nats/userauth.dart';
import 'package:nats_client/nats/nkeyauth.dart';
import 'package:nats_client/nats/jwtauth.dart';
import 'package:nats_client/nats/credauth.dart';

/*
 * Update the package name android/app/build.gradle
 *
 * defaultConfig {
        applicationId "com.YOURDOMAIN.APPNAME"
 *
 * Update all your device config files. Example Android OS:
 *
 * android/app/src/main/java/com/example/nats_client/MainActivity.java
 *
 * package com.YOURDOMAIN.APPNAME;

  import io.flutter.embedding.android.FlutterActivity;

  public class MainActivity extends FlutterActivity {
  }
 *
 * android/app/src/main/AndroidManifest.xml
 * android/app/src/debug/AndroidManifest.xml
 * android/app/src/profile/AndroidManifest.xml
 *
 * <manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.YOURDOMAIN.APPNAME">
 *
 *   <uses-permission android:name="android.permission.INTERNET" />
 *
 * SSL/TLS support
 * Create a folder /assets and copy your certificate *.p12
 * Define the path to the certificate in the pubspec.yaml file. Example:
    flutter:
      resources:
      -assets/cert.p12
 *
 * Compile and run:
 * flutter run --release -t test/demo.dart
 */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  TlsTrustedClient? tls;
  const authType = 0;
  const server = 'ws://127.0.0.1:8443';
  if (server.startsWith('wss')) {
    tls = TlsTrustedClient(await TlsTrustedClient.load('assets/cert.p12'), 'PASSWORD');
  }

  BaseAuthenticator? authenticator;
  switch(authType) {
    case 0:
      //nats-server -c token.conf -DV
      authenticator = UserAuthenticator('login_auth_token');
      break;
    case 1:
      //nats-server -c jwt.conf -DV
      authenticator = JwtAuthenticator('NATS USER JWT', 'USER NKEY SEED');
      break;
    case 2:
      //nats-server -c user_plain_pwd.conf -DV (plain)
      authenticator = UserAuthenticator('username', 'mypassword');
      break;
    case 3:
      //nats-server -c user_bcrypt_pwd.conf -DV (bcrypt)
      authenticator = UserAuthenticator('username', '01234-56789-98765-43210');
      break;
    case 4:
      //nats-server -c user_nkey_pwd.conf -DV (nkey)
      authenticator = NKeyAuthenticator('SUAOMTSAOJJNB5TIPMYC5W2OMXDS6ST3Z3PDLDJHCMTGV7SKWVPDL2OU3Y');
      break;
    case 5:
      //nats-server -c config.conf -DV
      const credsToken = '''-----BEGIN NATS USER JWT-----
  eyJ0eXAiOiJKV1QiLCJhbGciOiJlZDI1NTXBA...
  ------END NATS USER JWT------

  ************************* IMPORTANT *************************
  NKEY Seed printed below can be used to sign and prove identity.
  NKEYs are sensitive and should be treated as secrets.

  -----BEGIN USER NKEY SEED-----
  SUAD5DCLWCCHMYNJ6XFI6P5GX2VV7QN7HE5X74OBOCM2XZRSURLHN6EZXA
  ------END USER NKEY SEED------

  *************************************************************''';
      authenticator = CredsAuthenticator(credsToken);
      break;
  }

  final conn = await Nats.connect(
      opts: {
        'servers':  [server],
        'tls': tls
      },
      authenticator: authenticator,
      debug: true,
      statusCallback: (status, error) {
        log('$status (${error.toString()})');
      }
  );
  runApp(MyApp(conn));
}

class MyApp extends StatelessWidget {
  final Nats nats;

  const MyApp(this.nats, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const title = 'WebSocket Demo';
    return MaterialApp(
      title: title,
      home: MyHomePage(
        title: title, nats: nats
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key,
    required this.title,
    required this.nats
  }) : super(key: key);

  final String title;
  final Nats nats;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String streamText = '';

  @override
  void initState() {
    widget.nats.subscribe('user_a.>', (SubscriptionResult result) {
      log(utf8.decode(result.data));
      setState(() {
        streamText += '${utf8.decode(result.data)}\n';
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Form(
              child: TextFormField(
                focusNode: _focusNode,
                controller: _controller,
                decoration: const InputDecoration(labelText: 'Send a message'),
                onFieldSubmitted: (value) {
                  _sendMessage();
                  FocusScope.of(context).requestFocus(_focusNode);
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(streamText)
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendMessage,
        tooltip: 'Send message',
        child: const Icon(Icons.send),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _sendMessage() {
    if (_controller.text.isNotEmpty) {
      widget.nats.publish('user_a.test', utf8.encode(_controller.text));
      _controller.text = '';
    }
  }

  @override
  void dispose() {
    widget.nats.close();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }
}