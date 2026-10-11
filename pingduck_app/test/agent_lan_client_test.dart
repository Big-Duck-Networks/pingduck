import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/agent/data/agent_lan_client.dart';

/// A loopback server playing the agent's LAN API.
Future<(HttpServer, HttpAgentLanClient)> fakeAgent(Future<void> Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handle);
  addTearDown(() => server.close(force: true));
  return (server, HttpAgentLanClient(port: server.port));
}

Future<void> reply(HttpRequest r, int status, Object body) async {
  r.response.statusCode = status;
  r.response.headers.contentType = ContentType.json;
  r.response.write(jsonEncode(body));
  await r.response.close();
}

void main() {
  const info = {
    'app': 'pingduck-agent',
    'api': 1,
    'instance_id': 'inst-1',
    'name': 'homelab',
    'version': '0.9.0',
    'paired': false,
    'agent_id': null,
  };

  test('reads the info of a PingDuck agent', () async {
    final (_, client) = await fakeAgent((r) => reply(r, 200, info));
    final a = await client.info('127.0.0.1');
    expect(a?.name, 'homelab');
    expect(a?.paired, isFalse);
    expect(a?.ip, '127.0.0.1');
  });

  test('ignores anything that is not our agent', () async {
    final (_, client) = await fakeAgent((r) => reply(r, 200, {...info, 'app': 'something-else'}));
    expect(await client.info('127.0.0.1'), isNull);
    final (_, v2) = await fakeAgent((r) => reply(r, 200, {...info, 'api': 2}));
    expect(await v2.info('127.0.0.1'), isNull);
  });

  test('sends the code as JSON and reads the agent id', () async {
    String? contentType, body;
    final (_, client) = await fakeAgent((r) async {
      contentType = r.headers.contentType?.mimeType;
      body = await utf8.decoder.bind(r).join();
      await reply(r, 200, {'agent_id': 'agent-1', 'network_id': 'net-1'});
    });
    final result = await client.pair('127.0.0.1', 'ABCD2345');
    expect(result.outcome, PairOutcome.paired);
    expect(result.agentId, 'agent-1');
    expect(contentType, 'application/json');
    expect(jsonDecode(body!), {'code': 'ABCD2345'});
  });

  test('maps the agent errors', () async {
    for (final (status, error, outcome) in [
      (409, 'already_paired', PairOutcome.alreadyPaired),
      (400, 'invalid_code', PairOutcome.invalidCode),
      (400, 'bad_code', PairOutcome.unreachable),
      (429, 'busy', PairOutcome.busy),
      (502, 'upstream', PairOutcome.upstream),
    ]) {
      final (_, client) = await fakeAgent((r) => reply(r, status, {'error': error}));
      expect((await client.pair('127.0.0.1', 'ABCD2345')).outcome, outcome, reason: error);
    }
  });

  test('nobody listening is unreachable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final client = HttpAgentLanClient(port: port);
    expect((await client.pair('127.0.0.1', 'ABCD2345')).outcome, PairOutcome.unreachable);
    expect(await client.info('127.0.0.1'), isNull);
  });
}
