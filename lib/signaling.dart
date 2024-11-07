// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef StreamStateCallback = void Function(MediaStream stream);

class Signaling {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ]
      }
    ]
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  StreamStateCallback? onAddRemoteStream;
  bool isCaller = false;
  String? roomId;

  Future<void> startInstamatch() async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    CollectionReference waitingRoom = db.collection('waitingRoom');

    // Check for a waiting user
    QuerySnapshot querySnapshot = await waitingRoom.limit(1).get();
    if (querySnapshot.docs.isEmpty) {
      // No waiting users, add self to waiting room
      DocumentReference docRef =
          await waitingRoom.add({'createdAt': FieldValue.serverTimestamp()});

      // Listen for match
      docRef.snapshots().listen((snapshot) async {
        var data = snapshot.data() as Map<String, dynamic>;
        if (data.containsKey('roomId')) {
          roomId = data['roomId'];
          await joinRoom(roomId!);
          await docRef.delete();
        }
      });
    } else {
      // Match with the waiting user
      DocumentSnapshot waitingUser = querySnapshot.docs.first;
      roomId = await createRoom();
      await waitingRoom.doc(waitingUser.id).update({'roomId': roomId});
      await waitingRoom.doc(waitingUser.id).delete();
    }
  }

  Future<String> createRoom() async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc();
    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    var callerCandidatesCollection = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        print('Got candidate: ${candidate.toMap()}');
        callerCandidatesCollection.add(candidate.toMap());
      }
    };

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await roomRef.set({'offer': offer.toMap()});
    roomId = roomRef.id;

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onAddRemoteStream?.call(remoteStream!);
      }
    };

    roomRef.snapshots().listen((snapshot) async {
      var data = snapshot.data() as Map<String, dynamic>;
      RTCSessionDescription? remoteDescription =
          await peerConnection?.getRemoteDescription();
      if (remoteDescription == null && data['answer'] != null) {
        var answer = RTCSessionDescription(
            data['answer']['sdp'], data['answer']['type']);
        await peerConnection?.setRemoteDescription(answer);
      }
    });

    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(
                data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
        }
      }
    });

    isCaller = true;
    return roomId!;
  }

  Future<void> joinRoom(String roomId) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc(roomId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      peerConnection = await createPeerConnection(configuration);

      registerPeerConnectionListeners();

      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });

      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
      peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          calleeCandidatesCollection.add(candidate.toMap());
        }
      };

      peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          onAddRemoteStream?.call(remoteStream!);
        }
      };

      var data = roomSnapshot.data() as Map<String, dynamic>;
      var offer = data['offer'];
      await peerConnection?.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));

      var answer = await peerConnection!.createAnswer();
      await peerConnection!.setLocalDescription(answer);

      await roomRef.update({'answer': answer.toMap()});

      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            var data = change.doc.data() as Map<String, dynamic>;
            peerConnection!.addCandidate(
              RTCIceCandidate(
                  data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      });
      isCaller = false;
    }
  }

  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    var stream = await navigator.mediaDevices
        .getUserMedia({'video': true, 'audio': true});

    localVideo.srcObject = stream;
    localStream = stream;

    remoteVideo.srcObject = await createLocalMediaStream('remoteStream');
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    peerConnection?.close();
    localStream?.getTracks().forEach((track) {
      track.stop();
    });
    remoteStream?.getTracks().forEach((track) {
      track.stop();
    });

    if (roomId != null) {
      var db = FirebaseFirestore.instance;
      var roomRef = db.collection('rooms').doc(roomId);
      var calleeCandidates = await roomRef.collection('calleeCandidates').get();
      for (var document in calleeCandidates.docs) {
        await document.reference.delete();
      }
      var callerCandidates = await roomRef.collection('callerCandidates').get();
      for (var document in callerCandidates.docs) {
        await document.reference.delete();
      }
      await roomRef.delete();
    }

    localStream?.dispose();
    remoteStream?.dispose();
    peerConnection = null;
    roomId = null;
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onConnectionState = (state) {
      print('Connection state change: $state');
    };

    peerConnection?.onIceGatheringState = (state) {
      print('ICE gathering state changed: $state');
    };

    peerConnection?.onSignalingState = (state) {
      print('Signaling state change: $state');
    };

    peerConnection?.onIceConnectionState = (state) {
      print('ICE connection state change: $state');
    };
  }
}
