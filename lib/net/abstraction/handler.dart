abstract class Handler<In, Out> {
  Future<void> receive(In data, Chain<In, Out> chain);

  Future<void> send(Out data, Chain<In, Out> chain);

  Future<void> connect(Chain<In, Out> chain);

  Future<void> disconnect(Chain<In, Out> chain);
}

abstract class Chain<In, Out> {
  Future<void> send(In);
  Future<void> receive(Out);
  Future<void> connect();
  Future<void> disconnect();

}
