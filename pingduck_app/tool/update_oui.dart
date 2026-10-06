// Refreshes assets/oui_database/oui.csv from the IEEE registries.
//
//   dart run tool/update_oui.dart
//
// Keeps only the three columns pingduck-core reads (registry, assignment,
// organization) and drops the street addresses, which shrinks the asset by
// about two thirds and speeds up loading on phones.
import 'dart:convert';
import 'dart:io';

const sources = {
  'MA-L': 'https://standards-oui.ieee.org/oui/oui.csv',
  'MA-M': 'https://standards-oui.ieee.org/oui28/mam.csv',
  'MA-S': 'https://standards-oui.ieee.org/oui36/oui36.csv',
};

Future<void> main() async {
  final client = HttpClient()..userAgent = 'PingDuck OUI updater (+https://github.com/Big-Duck-Networks/pingduck)';
  final out = StringBuffer('Registry,Assignment,Organization Name\n');
  var total = 0;
  for (final MapEntry(key: registry, value: url) in sources.entries) {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('$url: HTTP ${res.statusCode}');
      exit(1);
    }
    final body = await res.transform(utf8.decoder).join();
    var n = 0;
    for (final line in const LineSplitter().convert(body).skip(1)) {
      final cols = _splitCsv(line, 3);
      if (cols.length < 3 || cols[0] != registry) continue;
      final name = cols[2].trim();
      if (name.isEmpty) continue;
      out.writeln('$registry,${cols[1]},${_quote(name)}');
      n++;
    }
    stdout.writeln('$registry: $n entries');
    total += n;
  }
  client.close();
  final file = File('assets/oui_database/oui.csv');
  await file.writeAsString(out.toString());
  stdout.writeln('wrote ${file.path}: $total entries, ${(await file.length()) ~/ 1024} KiB');
}

List<String> _splitCsv(String line, int maxFields) {
  final out = [StringBuffer()];
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
        out.last.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        out.last.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      if (out.length == maxFields) break;
      out.add(StringBuffer());
    } else if (c != '\r') {
      out.last.write(c);
    }
  }
  return [for (final b in out) b.toString()];
}

String _quote(String s) => s.contains(RegExp('[",]')) ? '"${s.replaceAll('"', '""')}"' : s;
