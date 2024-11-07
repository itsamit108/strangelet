// ignore_for_file: library_private_types_in_public_api

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:strangelet/firebase_options.dart';
import 'package:strangelet/signaling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    const MyApp(),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Instamatch Video Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    signaling.onAddRemoteStream = ((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });
  }

  @override
  void dispose() {
    signaling.hangUp(_localRenderer);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    bool isMobile = screenSize.width < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Instamatch Video Chat"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: isMobile
                    ? Column(
                        children: [
                          Expanded(
                            child: RTCVideoView(_localRenderer, mirror: true),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: RTCVideoView(_remoteRenderer),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: RTCVideoView(_localRenderer, mirror: true),
                          ),
                          Expanded(
                            child: RTCVideoView(_remoteRenderer),
                          ),
                        ],
                      ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    signaling.openUserMedia(_localRenderer, _remoteRenderer);
                  },
                  child: const Text("Open camera & microphone"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    signaling.startInstamatch();
                  },
                  child: const Text("Instamatch"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    signaling.hangUp(_localRenderer);
                    setState(() {
                      _remoteRenderer.srcObject = null;
                    });
                  },
                  child: const Text("Hangup"),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
