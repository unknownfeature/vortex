import 'dart:core';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:vortex/net/abstraction/handler.dart';
import 'package:vortex/net/abstraction/impl/noreplay/types.dart';

import '../../common/types.dart';


class NoReplayHandler extends Handler<Uint8List, Uint8List> {
  int _ourSeq = -1;
  int _peerSeq = -1;
  final Lock _lock = Lock(reentrant: true);

  @override
  Future<void> receive(Uint8List received, Chain<Uint8List, Uint8List> chain) async {
    return await _lock.synchronized(() async {
      final State current = State(_ourSeq, _peerSeq);
      State newState = await handle(received, current, chain);
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
      await chain.send(toSend + checksum(toSend));
      _ourSeq++;
    });
  }

  @override
  Future<void> connect(Chain<Uint8List, Uint8List> chain) async {
    await chain.connect();
    return await _lock.synchronized(() async {
      if (_ourSeq < 0 && _peerSeq < 0) {
        _ourSeq = random.nextInt(maxStartSequence);
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
        Num.uint8.write(PacketType.FIN.index) + Num.uint64.write(_ourSeq),
      );
      await chain.send(toSend + checksum(toSend));
      _ourSeq = _peerSeq = -1;
    });

    return await chain.disconnect();
  }
}
