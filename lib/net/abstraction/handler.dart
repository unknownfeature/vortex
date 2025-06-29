abstract class Handler<In, Out> {
  Future<void> connect();

  Future<void> receive(In data, Future<void> Function(Out) next);

  Future<void> send(Out data, Future<void> Function(In) next);
}
