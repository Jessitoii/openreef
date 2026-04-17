import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/skills/skill_exceptions.dart';
import 'package:openreef/skills/skill_frontmatter_parser.dart';

void main() {
  const parser = SkillFrontmatterParser();

  test('reads valid frontmatter and extracts runtime metadata', () {
    const markdown = '''---
name: Sleep Tracker
description: Track daily sleep reminders.
tools_required:
  - alarm_set
  - memory_search
trigger_patterns:
  - Sleep Reminder
  -  bedtime check
---
# Sleep Tracker
> Tracks daily sleep schedule.
''';

    final parsed = parser.parse(markdown);

    expect(parsed.manifest.name, 'Sleep Tracker');
    expect(parsed.manifest.description, 'Track daily sleep reminders.');
    expect(parsed.manifest.toolsRequired, <String>[
      'alarm_set',
      'memory_search',
    ]);
    expect(parsed.manifest.triggerPatterns, <String>[
      'sleep reminder',
      'bedtime check',
    ]);
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

    expect(() => parser.parse(markdown), throwsA(isA<SkillParseException>()));
  });

  test('defaults missing tools_required to an empty list', () {
    const markdown = '''---
memory_access: read_only
---
# Reminder
''';

    final parsed = parser.parse(markdown);

    expect(parsed.manifest.toolsRequired, isEmpty);
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

  test('rejects trigger_patterns values that are not a list of strings', () {
    const markdown = '''---
tools_required: [notify]
trigger_patterns:
  - ok
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
          'invalid_trigger_patterns',
        ),
      ),
    );
  });
}
