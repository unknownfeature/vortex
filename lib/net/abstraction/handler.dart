abstract class Handler<In, Out> {
  Future<void> connect();

  Future<In> receive(In);

  Future<void> send(Out out);
}
