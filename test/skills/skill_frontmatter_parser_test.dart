import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_frontmatter_parser.dart';

void main() {
  const parser = SkillFrontmatterParser();

  test('reads valid frontmatter and extracts tools_required', () {
    const markdown = '''---
tools_required:
  - alarm_set
  - memory_search
---
# Sleep Tracker
> Tracks daily sleep schedule.
''';

    final parsed = parser.parse(markdown);

    expect(parsed.manifest.toolsRequired, <String>['alarm_set', 'memory_search']);
  });

  test('preserves markdown body after frontmatter', () {
    const markdown = '''---
tools_required: [notify]
---
# Reminder
Body content.
''';

    final parsed = parser.parse(markdown);

    expect(parsed.body, '# Reminder\nBody content.\n');
  });

  test('rejects malformed yaml', () {
    const markdown = '''---
tools_required: [notify
---
# Reminder
''';

    expect(
      () => parser.parse(markdown),
      throwsA(isA<SkillParseException>()),
    );
  });

  test('rejects missing tools_required', () {
    const markdown = '''---
memory_access: read_only
---
# Reminder
''';

    expect(
      () => parser.parse(markdown),
      throwsA(
        isA<SkillParseException>().having(
          (error) => error.message,
          'message',
          'missing_tools_required',
        ),
      ),
    );
  });

  test('rejects tools_required values that are not a list of strings', () {
    const markdown = '''---
tools_required:
  - notify
  - 7
---
# Reminder
''';

    expect(
      () => parser.parse(markdown),
      throwsA(
        isA<SkillParseException>().having(
          (error) => error.message,
          'message',
          'invalid_tools_required',
        ),
      ),
    );
  });
}
