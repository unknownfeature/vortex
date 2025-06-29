import 'dart:collection';
import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import 'package:retry/retry.dart';
import 'package:vortex/net/abstraction/handler.dart';
import '../common/types.dart';

enum Packet { SYN, ACK, SYNACK, DATA }

extension PacketExtension on Packet {
  int expectedSize() {
    switch (this) {
      case Packet.SYN:
        return Num.uint64.bytes + Num.uint8.bytes;
      case Packet.ACK:
        return Num.uint64.bytes + Num.uint8.bytes;
      case Packet.SYNACK:
        return Num.uint64.bytes * 2 + Num.uint8.bytes;
      default:
        return -1;
    }
  }

  Uint8List extractData(Uint8List dataWithPacketType) {
    if (dataWithPacketType.length != expectedSize() && expectedSize() > 0) {
      throw Exception("invalid packet length");
    }
    int receivedType = Num.uint8.read(dataWithPacketType);
    if (receivedType != this.index) {
      throw Exception("invalid packet type");
    }
    return dataWithPacketType.sublist(Num.uint8.bytes);
  }


  static packetType(int ourSequence, peerSequence) {
    if (ourSequence < 0) {
      return peerSequence < 0 ? Packet.SYN : Packet.SYNACK;
    }
    if (peerSequence < 0) {
      return Packet.ACK;
    }
    return Packet.DATA;
  }

  Future<void> handle(Uint8List packet, Future<void> Function(Uint8List) downstreamAction) async {}
}

class ReplayHandler extends Handler<Uint8List, Uint8List> {
  int _ourSequence = -1;
  int _peersSequence = -1;
  final _random = Random();
  static const int _maxStartSequence = 4_294_967_296;

  ReplayHandler();

  @override
  Future<void> receive(Uint8List received,
      Chain<Uint8List, Uint8List> chain) async {
    Packet expected = PacketExtension.packetType(_ourSequence, _peersSequence);
    Uint8List data = expected.extractData(received);

    switch (expected) {
      case Packet.SYN:
        int peersSequence = Num.uint64.read(received.sublist(0));

        if (peersSequence < 0 || peersSequence > _maxStartSequence) {
          throw Exception("invalid our sequence returned");
        }
        _peersSequence = peersSequence + 1;

        List<int> packet = Num.uint8.write(Packet.ACK.index) + Num.uint64.write(_peersSequence);

        return await chain.prev(Uint8List.fromList(packet));

      case Packet.ACK:
        int increasedOurSequence = Num.uint64.read(received.sublist(0));

        if (increasedOurSequence != _ourSequence + 1) {
          throw Exception("invalid our sequence returned");
        }

        _ourSequence = increasedOurSequence;
        _peersSequence = _random.nextInt(_maxStartSequence);

        List<int> packet = Num.uint8.write(Packet.SYNACK.index) + Num.uint64.write(_ourSequence) +
            Num.uint64.write(_peersSequence++);

        return await chain.prev(Uint8List.fromList(packet));

      case Packet.SYNACK:
        int increasedPeersSequence = Num.uint64.read(received.sublist(0));

        if (increasedPeersSequence != _peersSequence) {
          throw Exception("invalid our sequence returned");
        }

        int ourSequence = Num.uint64.read(received.sublist(Num.uint64.bytes));

        if (ourSequence < 0 || ourSequence > _maxStartSequence) {
          throw Exception("invalid invalid our sequence");
        }

        _ourSequence = ourSequence;
        _peersSequence = increasedPeersSequence + 1;

      default:
        return await chain.next(data);
    }
  }

  @override
  Future<void> send(Uint8List out,
      Chain<Uint8List, Uint8List> chain) async {
    await _messageWriter.write(out, downstreamAction);
  }

  @override
  Future<void> connect(Chain<Uint8List, Uint8List> chain) async {
    if (_ourSequence >= 0 || _peersSequence >= 0) {
      throw Exception("already connected");
    }
    _ourSequence = _random.nextInt(_maxStartSequence);
    List<int> packet = Num.uint8.write(Packet.SYN.index);
    packet += Num.uint64.write(_ourSequence);
    return await chain.prev(Uint8List.fromList(packet));
  }

  @override
  Future<void> disconnect(Chain<Uint8List, Uint8List> chain)

  downstreamAction

  ) {
  // TODO: implement disconnect
  throw UnimplementedError();
  }
}
