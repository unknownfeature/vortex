abstract class Handler<In, Out> {

  Future<void> connect();

  Future<void> receive(In data);

  Future<void> send(Out data);
}
