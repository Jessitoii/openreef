import re

content = open('test/tools/core_tools_test.dart', encoding='utf-8').read()

# Add testContext variable declaration
content = content.replace(
    'late ToolManifestRegistry registry;',
    'late ToolManifestRegistry registry;\n  late ToolExecutionContext testContext;'
)

# Add testContext initialization in setUp, before the closing of setUp
content = content.replace(
    '    );\n  });\n\n  tearDown',
    "    );\n    testContext = ToolExecutionContext(\n      sessionKey: 'agent:main',\n      memoryStore: storage,\n      memoryIndex: memoryIndex,\n      settingsController: settingsController,\n      triggerRepository: triggerRepository,\n    );\n  });\n\n  tearDown"
)

# Add context: testContext to all registry.execute calls that lack it
# Find ');' that closes registry.execute( and insert context: testContext before it
def fix_execute(match):
    text = match.group(0)
    if 'context:' in text:
        return text
    # Insert context: testContext, before the last closing );
    idx = text.rfind('\n    );')
    if idx == -1:
        idx = text.rfind('\n      );')
    if idx == -1:
        return text
    return text[:idx] + '\n      context: testContext,' + text[idx:]

content = re.sub(
    r'registry\.execute\([^;]+;',
    fix_execute,
    content,
    flags=re.DOTALL
)

open('test/tools/core_tools_test.dart', 'w', encoding='utf-8').write(content)
print('Done')
