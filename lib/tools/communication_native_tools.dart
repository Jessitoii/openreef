import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';

class PhoneCallToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'phone_call',
    description: 'Make a direct phone call.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'number', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Call initiated.');
  }
}

class PhoneDialToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'phone_dial',
    description: 'Open the dialer.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'number', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Dialer opened.');
  }
}

class SmsSendToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'sms_send',
    description: 'Send an SMS message.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'number', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'message', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'SMS sent.');
  }
}

class WhatsappDraftToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'communication_whatsapp_draft',
    description: 'Draft a WhatsApp message.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'message', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'number',
        type: ToolArgumentType.string,
        isRequired: false,
      ),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'WhatsApp opened.');
  }
}

class TelegramDraftToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'communication_telegram_draft',
    description: 'Draft a Telegram message.',
    category: 'communication',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'message', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Telegram opened.');
  }
}
