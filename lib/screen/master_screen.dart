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
  static const double _descriptionFontSize = 20;
  static const double _fieldFontSize = 26;
  static const double _rowHeight = 64;
  static const double _nameFieldWidth = 560;
  static const double _addButtonMinWidth = 140;
  static const double _deleteIconSize = 32;

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
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add groups (shirt, pant, etc.) for the sales bill dropdown.',
                  style: TextStyle(
                    fontSize: _descriptionFontSize,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: _nameFieldWidth,
                      height: _rowHeight,
                      child: TextField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addItem(),
                        style: const TextStyle(
                          fontSize: _fieldFontSize,
                          height: 1,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Item name',
                          labelStyle: TextStyle(fontSize: _fieldFontSize),
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: _rowHeight,
                      child: ElevatedButton(
                        onPressed: _addItem,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(_addButtonMinWidth, _rowHeight),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          textStyle: const TextStyle(
                            fontSize: _fieldFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('ADD'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 20),
                  ),
                ],
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_items.isEmpty)
                  const Text(
                    'No items yet. Add your first item above.',
                    style: TextStyle(fontSize: _descriptionFontSize),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final name = _items[index];
                        return SizedBox(
                          height: _rowHeight,
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    name.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: _fieldFontSize,
                                      fontWeight: FontWeight.w600,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                iconSize: _deleteIconSize,
                                tooltip: 'Remove',
                                onPressed: () => _deleteItem(name),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
