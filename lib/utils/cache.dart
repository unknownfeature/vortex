import 'package:synchronized/synchronized.dart';

class LRUCache<K extends Comparable<K>, V> {
  final Map<K, V> _inner = {};
  final Map<int, K> _timesAdded = {};
  final Lock _lock = new Lock(reentrant: true);
  final int _expireAfterSeconds;

  LRUCache(this._expireAfterSeconds);

  Future<void> _cleanUp() async {
    int now = (DateTime.now().millisecondsSinceEpoch / 1000) as int;
    await this._lock.synchronized(
      () => _timesAdded.removeWhere((k, _) => k + this._expireAfterSeconds < now),
    );
  }

  // returns new value
  Future<V> compute(K k, V Function(K, V?) computer) async {
    return await this._lock.synchronized(
      () => this._cleanUp().then((_) {
        V newOne = computer(k, this._inner[k]);
        this._inner[k] = newOne;
        return newOne;
      }),
    );
  }

  Future<V?> get(K k) async {
    return await this._lock.synchronized(() => this._cleanUp().then((_) => this._inner[k]));
  }

  Future<V?> remove(K k) async {
    return await this._lock.synchronized(() => this._cleanUp().then((_) => this._inner.remove(k)));
  }
}
