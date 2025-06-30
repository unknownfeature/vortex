import 'dart:math';
import 'dart:typed_data';

enum Num { uint8, uint16, uint32, uint64 }

extension SizeExtension on Num {
  int get max {
    return pow(2, bits) - 1 as int;
  }
  int get bytes {
    return pow(2, index) as int;
  }

  int get bits {
    return 8 * bytes;
  }

  Uint8List write(int number, [Endian endian = Endian.big]) {
    final byteData = ByteData(bytes);

    switch (this) {
      case Num.uint8:
        byteData.setUint8(0, number);
      case Num.uint16:
        byteData.setUint16(0, number, endian);
      case Num.uint32:
        byteData.setUint32(0, number, endian);
      case Num.uint64:
        byteData.setUint64(0, number, endian);
    }
    return byteData.buffer.asUint8List();
  }

  int read(Uint8List data, [Endian endian = Endian.big]) {
    if (data.lengthInBytes < bytes) {
      throw Exception("not enough bytes to extract number");
    }
    switch (this) {
      case Num.uint8:
        return ByteData.sublistView(data).getUint8(0);
      case Num.uint16:
        return ByteData.sublistView(data).getUint16(0, endian);
      case Num.uint32:
        return ByteData.sublistView(data).getUint32(0, endian);
      case Num.uint64:
        return ByteData.sublistView(data).getUint64(0, endian);
    }
  }
}
