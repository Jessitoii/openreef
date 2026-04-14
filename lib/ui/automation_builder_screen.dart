import 'package:flutter/material.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/automation_models.dart';

class AutomationBuilderCatalog {
  static AutomationEditorDraft defaultDraft() {
    return AutomationEditorDraft.create(AutomationEditorKind.schedule);
  }
}

class AutomationBuilderScreen extends StatefulWidget {
  const AutomationBuilderScreen({
    required this.controller,
    required this.initialDraft,
    super.key,
  });

  final AutomationController controller;
  final AutomationEditorDraft initialDraft;

  @override
  State<AutomationBuilderScreen> createState() => _AutomationBuilderScreenState();
}

class _AutomationBuilderScreenState extends State<AutomationBuilderScreen> {
  late AutomationEditorDraft _draft;
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late final TextEditingController _rawCronController;
  late final TextEditingController _rawSourceController;
  late final TextEditingController _rawEventController;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft;
    _nameController = TextEditingController(text: _draft.name);
    _promptController = TextEditingController(text: _draft.actionPrompt);
    _rawCronController = TextEditingController(text: _draft.rawCron ?? '');
    _rawSourceController = TextEditingController(text: _draft.rawSourceId ?? '');
    _rawEventController = TextEditingController(text: _draft.rawEventId ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _rawCronController.dispose();
    _rawSourceController.dispose();
    _rawEventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create automation'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_summary()),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (value) => setState(() => _draft = _draft.copyWith(name: value)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(labelText: 'What should OpenReef do?'),
            minLines: 2,
            maxLines: 4,
            onChanged: (value) => setState(() => _draft = _draft.copyWith(actionPrompt: value)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AutomationEditorKind>(
            initialValue: _draft.kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: AutomationEditorKind.schedule, child: Text('At a specific time')),
              DropdownMenuItem(value: AutomationEditorKind.interval, child: Text('Repeating interval')),
              DropdownMenuItem(value: AutomationEditorKind.battery, child: Text('When battery gets low')),
              DropdownMenuItem(value: AutomationEditorKind.mcpEvent, child: Text('Connected service event')),
              DropdownMenuItem(value: AutomationEditorKind.standingOrder, child: Text('Standing order')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _draft = AutomationEditorDraft.create(value));
            },
          ),
          const SizedBox(height: 12),
          if (_draft.kind == AutomationEditorKind.schedule) ...[
            TextFormField(
              decoration: const InputDecoration(labelText: 'Time of day'),
              initialValue:
                  '${_draft.timeOfDay?.hour.toString().padLeft(2, '0')}:${_draft.timeOfDay?.minute.toString().padLeft(2, '0')}',
              onChanged: (value) {
                final parts = value.split(':');
                if (parts.length == 2) {
                  final hour = int.tryParse(parts[0]);
                  final minute = int.tryParse(parts[1]);
                  if (hour != null && minute != null) {
                    setState(() {
                      _draft = _draft.copyWith(
                        timeOfDay: TimeOfDay(hour: hour, minute: minute),
                      );
                    });
                  }
                }
              },
            ),
          ] else if (_draft.kind == AutomationEditorKind.interval) ...[
            TextField(
              decoration: const InputDecoration(labelText: 'Repeat interval (minutes)'),
              keyboardType: TextInputType.number,
              onChanged: (value) => setState(() => _draft = _draft.copyWith(repeatInterval: int.tryParse(value))),
            ),
          ] else if (_draft.kind == AutomationEditorKind.battery) ...[
            TextField(
              decoration: const InputDecoration(labelText: 'Battery threshold'),
              keyboardType: TextInputType.number,
              onChanged: (value) => setState(() => _draft = _draft.copyWith(batteryThreshold: int.tryParse(value))),
            ),
          ] else if (_draft.kind == AutomationEditorKind.standingOrder) ...[
            const Text('Always-on rule that applies when its conditions match.'),
          ] else if (_draft.kind == AutomationEditorKind.boot || _draft.kind == AutomationEditorKind.manual) ...[
            const Text('Read-only visible type. Creation is disabled.'),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced'),
            value: _advanced,
            onChanged: (value) => setState(() => _advanced = value),
          ),
          if (_advanced) ...[
            TextButton(
              onPressed: () => setState(
                () => _draft = _draft.copyWith(kind: AutomationEditorKind.cron),
              ),
              child: const Text('Use advanced cron schedule'),
            ),
            TextField(
              controller: _rawCronController,
              decoration: const InputDecoration(labelText: 'Cron expression'),
              onChanged: (value) => setState(() => _draft = _draft.copyWith(rawCron: value)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rawSourceController,
              decoration: const InputDecoration(labelText: 'Source id'),
              onChanged: (value) => setState(() => _draft = _draft.copyWith(rawSourceId: value)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rawEventController,
              decoration: const InputDecoration(labelText: 'Event id'),
              onChanged: (value) => setState(() => _draft = _draft.copyWith(rawEventId: value)),
            ),
          ],
        ],
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(
      _draft.copyWith(
        name: _nameController.text,
        actionPrompt: _promptController.text,
      ),
    );
  }

  String _summary() {
    final name = _nameController.text.trim().isEmpty ? 'This automation' : _nameController.text.trim();
    return switch (_draft.kind) {
      AutomationEditorKind.schedule => '$name runs at a chosen time.',
      AutomationEditorKind.interval => '$name repeats on an interval.',
      AutomationEditorKind.cron => '$name uses an advanced schedule.',
      AutomationEditorKind.battery => '$name runs when battery gets low.',
      AutomationEditorKind.mcpEvent => '$name runs when a connected service emits an event.',
      AutomationEditorKind.boot => '$name runs when the phone starts.',
      AutomationEditorKind.manual => '$name runs manually.',
      AutomationEditorKind.standingOrder => '$name always applies when conditions match.',
    };
  }
}
