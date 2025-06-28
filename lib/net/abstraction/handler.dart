abstract class Handler<In, Out> {
  Future<void> connect();

  Future<void> receive(In);

  Future<void> send(Out out);
}
