import 'dart:async';
import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import 'package:vortex/net/abstraction/handler.dart';

import '../../common/types.dart';

final random = Random();
const int maxStartSequence = 4_294_967_296;

Uint8List checksum(Uint8List packet) {
  return Num.uint16.write(packet.reduce((one, two) => (one + two) % Num.uint16.max));
}

Future<State> handle(Uint8List packet, State state, Chain<Uint8List, Uint8List> chain) {
  if (packet.length < Num.uint16.bytes) {
    throw Exception("packet too short");
  }
  Uint8List chksm = packet.sublist(packet.length - Num.uint16.bytes);
  Uint8List dataWithoutChecksum = packet.sublist(0, packet.length - Num.uint16.bytes);

  if (checksum(dataWithoutChecksum) != chksm) {
    throw Exception("checksum didn't match");
  }
  PacketType receivedType = PacketType.values[Num.uint8.read(dataWithoutChecksum)];
  final int expectedSize = receivedType._expectedSize();

  if (packet.length != expectedSize && expectedSize >= 0) {
    throw Exception("invalid packet length");
  }
  return receivedType._handle(dataWithoutChecksum.sublist(Num.uint8.bytes), state, chain);
}

enum PacketType { SYN, ACK, SYNACK, DATA, FIN }

class State {
  final int ourSequence;
  final int peerSequence;

  State(this.ourSequence, this.peerSequence);
}

extension Extension on PacketType {
  int _expectedSize() {
    switch (this) {
      case PacketType.SYN:
        return Num.uint64.bytes + Num.uint8.bytes + Num.uint16.bytes;
      case PacketType.ACK:
        return Num.uint64.bytes + Num.uint8.bytes + Num.uint16.bytes;
      case PacketType.SYNACK:
        return Num.uint64.bytes * 2 + Num.uint8.bytes + Num.uint16.bytes;
      case PacketType.FIN:
        return Num.uint64.bytes + Num.uint8.bytes + Num.uint16.bytes;
      case PacketType.DATA:
        return -1;
    }
  }

  Future<State> _handle(Uint8List data, State state, Chain<Uint8List, Uint8List> chain) async {
    switch (this) {
      case PacketType.SYN:
        int peersSequence = Num.uint64.read(data.sublist(0));

        if (peersSequence < 0 || peersSequence > maxStartSequence) {
          throw Exception("invalid our sequence returned");
        }
        peersSequence++;

        var toSend = Uint8List.fromList(
          Num.uint8.write(PacketType.ACK.index) + Num.uint64.write(peersSequence),
        );
        unawaited(chain.send(toSend + checksum(toSend)));
        return State(state.ourSequence, peersSequence);

      case PacketType.ACK:
        int increasedOurSequence = Num.uint64.read(data.sublist(0));

        if (increasedOurSequence != state.ourSequence + 1) {
          throw Exception("invalid our sequence returned");
        }
        int peerSequence = random.nextInt(maxStartSequence);
        increasedOurSequence++;
        var toSend = Uint8List.fromList(
          Num.uint8.write(PacketType.SYNACK.index) +
              Num.uint64.write(increasedOurSequence) +
              Num.uint64.write(peerSequence),
        );
        unawaited(chain.send(toSend + checksum(toSend)));
        return State(increasedOurSequence, peerSequence);

      case PacketType.SYNACK:
        int increasedPeersSequence = Num.uint64.read(data.sublist(0));

        if (increasedPeersSequence <= state.peerSequence) {
          throw Exception("invalid our sequence returned");
        }

        int ourSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));

        if (ourSequence < 0 || ourSequence > maxStartSequence) {
          throw Exception("invalid invalid our sequence");
        }
        return State(ourSequence + 1, increasedPeersSequence);
      case PacketType.FIN:
        int peerSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));

        if (peerSequence <= state.peerSequence) {
          throw Exception("invalid sequence");
        }
        return State(-1, -1);

      case PacketType.DATA:
        int peerSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));

        if (peerSequence <= state.peerSequence) {
          throw Exception("invalid sequence");
        }
        unawaited(chain.receive(data.sublist(Num.uint64.bytes)));

        return State(state.ourSequence, peerSequence);
    }
  }
}