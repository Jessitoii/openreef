import 'package:openreef/ui/automation_models.dart';

class AutomationCatalog {
  static const supportedCreateKinds = <AutomationEditorKind>[
    AutomationEditorKind.schedule,
    AutomationEditorKind.interval,
    AutomationEditorKind.cron,
    AutomationEditorKind.battery,
    AutomationEditorKind.mcpEvent,
    AutomationEditorKind.standingOrder,
  ];
}
