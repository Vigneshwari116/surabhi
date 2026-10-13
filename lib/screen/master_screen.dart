import 'package:flutter/material.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/theme/app_theme.dart';
import 'package:surabhi/widgets/compact_layout.dart';

/// Item master (shirt, pant, etc.) used on the sales bill dropdown.
class MasterScreen extends StatefulWidget {
  const MasterScreen({super.key});

  @override
  State<MasterScreen> createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  List<String> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final names = await LocalDb.instance.listMasterItemNames();
      if (!mounted) return;
      setState(() {
        _items = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load master items';
      });
    }
  }

  Future<void> _addItem() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter an item name');
      return;
    }
    final exists = _items.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      setState(() => _error = 'Same item name already exists');
      return;
    }
    try {
      await LocalDb.instance.insertMasterItem(name);
      _nameCtrl.clear();
      setState(() => _error = null);
      await _reload();
    } catch (_) {
      setState(() => _error = 'Same item name already exists');
    }
  }

  Future<void> _deleteItem(String name) async {
    await LocalDb.instance.deleteMasterItem(name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar('MASTER'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add groups (shirt, pant, etc.) for the sales bill dropdown.',
                style: TextStyle(fontSize: 12, color: AppColors.navy),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addItem(),
                      decoration: const InputDecoration(
                        labelText: 'Item name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addItem,
                    child: const Text('ADD'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_items.isEmpty)
                const Text(
                  'No items yet. Add your first item above.',
                  style: TextStyle(fontSize: 12),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final name = _items[index];
                      return ListTile(
                        dense: true,
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove',
                          onPressed: () => _deleteItem(name),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

