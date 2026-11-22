import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('native sqlite3 loads under flutter test (native assets)', () {
    final db = sqlite3.openInMemory();
    db.execute('CREATE TABLE probe (id INTEGER PRIMARY KEY, name TEXT)');
    db.execute("INSERT INTO probe (name) VALUES ('hello')");
    final rows = db.select('SELECT name FROM probe');
    expect(rows.single['name'], 'hello');
    db.close();
  });
}
