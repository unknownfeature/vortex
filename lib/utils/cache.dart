import 'package:synchronized/synchronized.dart';

class _TimedValue<V> {
  final V _v;
  final int _time;


  _TimedValue(this._v, this._time);

  V get value => _v;
  int get time => _time;
}

// todo UT
class LRUCache<K, V> {
  final Map<K, _TimedValue<V>> _inner = {};
  final Lock _lock = Lock(reentrant: false);
  final int _expireAfterSeconds;

  LRUCache(this._expireAfterSeconds);

  Future<void> _cleanUp() async {
    int now = (DateTime.now().millisecondsSinceEpoch / 1000) as int;
    await _lock.synchronized(
      () => _inner.removeWhere((k, v) => v.time + _expireAfterSeconds < now),
    );
  }


  // returns new value
  Future<V> compute(K k, V Function(K, V?) computer) async {
    return await _lock.synchronized(
      () => _cleanUp().then((_) {
        V newOne = computer(k, _inner[k]?.value);
        _inner[k] =_TimedValue(newOne, (DateTime.now().millisecondsSinceEpoch / 1000) as int);
        return newOne;
      }),
    );
  }

  Future<V?> get(K k) async {
    return await _lock.synchronized(() => _cleanUp().then((_) => _inner[k]?.value));
  }

  Future<V?> remove(K k) async {
    return await _lock.synchronized(() => _cleanUp().then((_) => _inner.remove(k)?.value));
  }
}
