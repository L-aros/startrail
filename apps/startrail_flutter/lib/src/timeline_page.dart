import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:domain/domain.dart';

import 'vault_backend.dart';

/// 解锁后的时间线：按事件时间倒序浏览、搜索、新建/编辑/删除条目。
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.backend, required this.onLock});

  final VaultBackend backend;
  final VoidCallback onLock;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _searchController = TextEditingController();
  List<Map<String, Object?>> _entries = const [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.backend.timeline();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _entries = (result.data as List).cast<Map<String, Object?>>();
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _search(String query) async {
    final result = await widget.backend.search(query);
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _entries = (result.data as List).cast<Map<String, Object?>>();
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _openEditor([Map<String, Object?>? existing]) async {
    final draft = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) =>
          _EntryEditorDialog(backend: widget.backend, existing: existing),
    );
    if (draft == null || !mounted) return;
    await _save(draft, existing: existing);
  }

  Future<void> _delete(Map<String, Object?> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除会写入墓碑对象，记录不再出现在时间线。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.backend.deleteEntry(
      entry['id'] as String,
      entry['revision'] as int,
    );
    if (!mounted) return;
    if (!result.ok) {
      _showError(result.error ?? '删除失败');
      return;
    }
    _reload();
  }

  Future<void> _save(
    Map<String, Object?> draft, {
    Map<String, Object?>? existing,
  }) async {
    final result = existing == null
        ? await widget.backend.createEntry(draft)
        : await widget.backend.updateEntry(
            existing['id'] as String,
            existing['revision'] as int,
            draft,
          );
    if (!mounted) return;
    if (!result.ok) {
      _showError(result.error ?? '保存失败');
      return;
    }
    _reload();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('时间线'),
        actions: [
          IconButton(
            tooltip: '锁定',
            icon: const Icon(Icons.lock),
            onPressed: widget.onLock,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('entry-search'),
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索记录',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建记录',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, key: const Key('timeline-error')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('还没有记录，点右下角新建一条吧。'));
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _EntryCard(
          entry: entry,
          onTap: () => _openEditor(entry),
          onDelete: () => _delete(entry),
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, Object?> entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tags = (entry['tags'] as List).cast<Map<String, Object?>>();
    final mood = entry['mood'] as String?;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry['body'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (mood != null) Text(mood),
                  Text(
                    _formatTime(entry['occurred_at'] as String),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final tag in tags)
                    Chip(
                      label: Text(tag['name'] as String),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    tooltip: '删除',
                    iconSize: 18,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新建/编辑条目对话框：正文、心情、标签（逗号分隔）、附件。
class _EntryEditorDialog extends StatefulWidget {
  const _EntryEditorDialog({required this.backend, this.existing});

  final VaultBackend backend;
  final Map<String, Object?>? existing;

  @override
  State<_EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends State<_EntryEditorDialog> {
  late final TextEditingController _body;
  late final TextEditingController _mood;
  late final TextEditingController _tags;
  DateTime _occurredAt = DateTime.now();
  List<Map<String, Object?>> _attachments = const [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _body = TextEditingController(text: existing?['body'] as String? ?? '');
    _mood = TextEditingController(text: existing?['mood'] as String? ?? '');
    final existingTags = existing == null
        ? const <Map<String, Object?>>[]
        : (existing['tags'] as List).cast<Map<String, Object?>>();
    _tags = TextEditingController(
      text: existingTags.map((t) => t['name']).join(', '),
    );
    if (existing != null) {
      _occurredAt = DateTime.parse(existing['occurred_at'] as String);
      _attachments = (existing['attachments'] as List)
          .cast<Map<String, Object?>>();
    }
  }

  @override
  void dispose() {
    _body.dispose();
    _mood.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新建记录' : '编辑记录'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('entry-body'),
              controller: _body,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '正文',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-mood'),
              controller: _mood,
              decoration: const InputDecoration(
                labelText: '心情（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-tags'),
              controller: _tags,
              decoration: const InputDecoration(
                labelText: '标签（逗号分隔）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('entry-add-attachment'),
                icon: const Icon(Icons.attach_file),
                label: const Text('添加附件'),
                onPressed: _pickAttachment,
              ),
            ),
            for (final attachment in _attachments)
              _AttachmentTile(
                attachment: attachment,
                onRemove: () => setState(() {
                  _attachments = [
                    for (final a in _attachments)
                      if (a['id'] != attachment['id']) a,
                  ];
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final body = _body.text.trim();
    if (body.isEmpty) return;
    final existing = widget.existing;
    final existingTags = existing == null
        ? const <Map<String, Object?>>[]
        : (existing['tags'] as List).cast<Map<String, Object?>>();
    final draft = <String, Object?>{
      'occurred_at': _occurredAt.toUtc().toIso8601String(),
      'body': body,
      'mood': _mood.text.trim().isEmpty ? null : _mood.text.trim(),
      'tags': _parseTags(_tags.text, existingTags),
      'attachments': _attachments,
    };
    Navigator.pop(context, draft);
  }

  Future<void> _pickAttachment() async {
    const typeGroup = XTypeGroup(label: '附件');
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final result = await widget.backend.importAttachment(
      file.path,
      file.mimeType ?? 'application/octet-stream',
    );
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '附件导入失败')));
      return;
    }
    setState(() {
      _attachments = [
        ..._attachments,
        (result.data as Map).cast<String, Object?>(),
      ];
    });
  }
}

/// 编辑器中的单个附件条目：mime、大小与移除按钮。
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final Map<String, Object?> attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mime = attachment['mime'] as String;
    final byteSize = attachment['byte_size'] as int;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(mime, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(_formatBytes(byteSize)),
      trailing: IconButton(
        tooltip: '移除附件',
        iconSize: 18,
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

List<Map<String, Object?>> _parseTags(
  String text,
  List<Map<String, Object?>> existing,
) {
  final names = text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  return [for (final name in names) _tagWithExisting(name, existing)];
}

Map<String, Object?> _tagWithExisting(
  String name,
  List<Map<String, Object?>> existing,
) {
  for (final tag in existing) {
    if (normalizeTagName(tag['name'] as String) == normalizeTagName(name)) {
      return {'id': tag['id'], 'name': name, 'color': tag['color']};
    }
  }
  return {'id': _uuid(), 'name': name, 'color': 0xff465d91};
}

String _formatTime(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
