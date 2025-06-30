import 'dart:async';
import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:vortex/net/abstraction/handler.dart';

import '../common/types.dart';

final _random = Random();
const int _maxStartSequence = 4_294_967_296;

Uint8List _checksum(Uint8List packet) {
  return Num.uint16.write(packet.reduce((one, two) => (one + two) % Num.uint16.max));
}

Future<State> _handle(Uint8List packet, State state, Chain<Uint8List, Uint8List> chain) {
  if (packet.length < Num.uint16.bytes) {
    throw Exception("packet too short");
  }
  Uint8List chksm = packet.sublist(packet.length - Num.uint16.bytes);
  Uint8List dataWithoutChecksum = packet.sublist(0, packet.length - Num.uint16.bytes);

  if (_checksum(dataWithoutChecksum) != chksm) {
    throw Exception("checksum didn't match");
  }
  PacketType receivedType = PacketType.values[Num.uint8.read(dataWithoutChecksum)];
  final int expectedSize = receivedType._expectedSize();

  if (packet.length != expectedSize && expectedSize >= 0) {
    throw Exception("invalid packet length");
  }
  return receivedType._handle(dataWithoutChecksum.sublist(Num.uint8.bytes), state, chain);
}

enum PacketType { SYN, ACK, SYNACK, DATA, DISCONNECT }

class State {
  final ourSequence;
  final peerSequence;

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
      case PacketType.DISCONNECT:
        return Num.uint64.bytes + Num.uint8.bytes + Num.uint16.bytes;
      case PacketType.DATA:
        return -1;
    }
  }

  Future<State> _handle(Uint8List data, State state, Chain<Uint8List, Uint8List> chain) async {
    switch (this) {
      case PacketType.SYN:
        int peersSequence = Num.uint64.read(data.sublist(0));

        if (peersSequence < 0 || peersSequence > _maxStartSequence) {
          throw Exception("invalid our sequence returned");
        }
        peersSequence++;

        var toSend = Uint8List.fromList(
          Num.uint8.write(PacketType.ACK.index) + Num.uint64.write(peersSequence),
        );
        unawaited(chain.send(toSend + _checksum(toSend)));
        return State(state.ourSequence, peersSequence);

      case PacketType.ACK:
        int increasedOurSequence = Num.uint64.read(data.sublist(0));

        if (increasedOurSequence != state.ourSequence + 1) {
          throw Exception("invalid our sequence returned");
        }
        int peerSequence = _random.nextInt(_maxStartSequence);
        increasedOurSequence++;
        var toSend = Uint8List.fromList(
          Num.uint8.write(PacketType.SYNACK.index) +
              Num.uint64.write(increasedOurSequence) +
              Num.uint64.write(peerSequence),
        );
        unawaited(chain.send(toSend + _checksum(toSend)));
        return State(increasedOurSequence, peerSequence);

      case PacketType.SYNACK:
        int increasedPeersSequence = Num.uint64.read(data.sublist(0));

        if (increasedPeersSequence <= state.peerSequence) {
          throw Exception("invalid our sequence returned");
        }

        int ourSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));

        if (ourSequence < 0 || ourSequence > _maxStartSequence) {
          throw Exception("invalid invalid our sequence");
        }
        return State(ourSequence + 1, increasedPeersSequence);
      case PacketType.DISCONNECT:
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

class ReplayHandler extends Handler<Uint8List, Uint8List> {
  int _ourSeq = -1;
  int _peerSeq = -1;
  final Lock _lock = Lock(reentrant: false);

  @override
  Future<void> receive(Uint8List received, Chain<Uint8List, Uint8List> chain) async {
    return await _lock.synchronized(() async {
      final State current = State(_ourSeq, _peerSeq);
      State newState = await _handle(received, current, chain);
      _ourSeq = newState.ourSequence;
      _peerSeq = newState.peerSequence;
    });
  }

  @override
  Future<void> send(Uint8List out, Chain<Uint8List, Uint8List> chain) async {
    await _lock.synchronized(() async {
      if (_ourSeq < 0 || _peerSeq < 0) {
        throw Exception("connection in progress, can't sent");
      }

      // todo should we retry?
      var toSend = Uint8List.fromList(
        Num.uint8.write(PacketType.DATA.index) + Num.uint64.write(_ourSeq) + out,
      );
      await chain.send(toSend + _checksum(toSend));
      _ourSeq++;
    });
  }

  @override
  Future<void> connect(Chain<Uint8List, Uint8List> chain) async {
    await chain.connect();
    return await _lock.synchronized(() async {
      if (_ourSeq < 0 && _peerSeq < 0) {
        _ourSeq = _random.nextInt(_maxStartSequence);
        List<int> packet = Num.uint8.write(PacketType.SYN.index);
        packet += Num.uint64.write(_ourSeq);
        await chain.send(Uint8List.fromList(packet));
      }
      {
        throw Exception("connection in progress or already connected");
      }
    });
  }

  @override
  Future<void> disconnect(Chain<Uint8List, Uint8List> chain) async {
    await _lock.synchronized(() async {
      var toSend = Uint8List.fromList(
        Num.uint8.write(PacketType.DISCONNECT.index) + Num.uint64.write(_ourSeq),
      );
      await chain.send(toSend + _checksum(toSend));
      _ourSeq = _peerSeq = -1;
    });

    return await chain.disconnect();
  }
}
