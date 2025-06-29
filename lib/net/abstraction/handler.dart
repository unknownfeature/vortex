abstract class Handler<In, Out> {
  Future<void> connect(Chain<In, Out> chain) async => {};

  Future<void> disconnect(Chain<In, Out> chain) async => {};

  Future<void> receive(In data, Chain<In, Out> chain);

  Future<void> send(Out data, Chain<In, Out> chain);
}


abstract class Chain<In, Out> {
  Future<void> Function(In) prev;
  Future<void> Function(Out) next;

}