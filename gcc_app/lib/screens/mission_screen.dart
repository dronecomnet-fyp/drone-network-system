/// Mission setup (M7b): the operation's identity, resource inventory, and
/// deployment list. All local and offline; the roster is editable at any
/// time, including in the field when a volunteer arrives with a drone.
///
/// Product specs are fetched from the product site while online (M7c) or
/// entered manually so the field stays fully offline-capable.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ai_advisor.dart';
import '../services/product_api.dart';
import '../state/app_state.dart';
import '../state/mission_state.dart';

/// Fetch a unit's specs from the product site (online) and cache them into
/// the mission so they resolve offline afterwards. Shared by the drone and
/// module rows.
Future<void> fetchUnitSpecs(
    BuildContext context, MissionState mission, String unitId) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  if (!app.productApiConfigured) {
    messenger.showSnackBar(const SnackBar(
        content: Text(
            'Set the product site URL and anon key in Settings first.')));
    return;
  }
  final api = ProductApi(baseUrl: app.productApiUrl, anonKey: app.productApiKey);
  try {
    final info = await api.fetchUnit(unitId);
    mission.cacheProduct(unitId, info);
    messenger.showSnackBar(
        SnackBar(content: Text('Fetched ${info.name} for $unitId')));
  } on ProductApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    api.close();
  }
}

class MissionScreen extends StatelessWidget {
  const MissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Mission', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text(m.loadedFrom == null ? 'not saved' : 'file loaded',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        _MissionInfoCard(),
        const SizedBox(height: 8),
        _ResourceCountsCard(),
        const SizedBox(height: 8),
        _ModulesCard(),
        const SizedBox(height: 8),
        _DronesCard(),
        const SizedBox(height: 8),
        _DeploymentsCard(),
      ],
    );
  }
}

class _MissionInfoCard extends StatelessWidget {
  static const _types = ['flood', 'earthquake', 'landslide', 'cyclone', 'fire', 'other'];

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    final nameCtrl = TextEditingController(text: m.missionName);
    final challengeCtrl = TextEditingController();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Identity', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Mission name', hintText: 'e.g. Flood 2026'),
                    onSubmitted: (v) => m.setMissionInfo(name: v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _types.contains(m.disasterType)
                      ? m.disasterType
                      : 'other',
                  items: _types
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => m.setMissionInfo(type: v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Challenges', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...m.challenges.map((c) => Chip(
                      label: Text(c),
                      onDeleted: () => m.removeChallenge(c),
                    )),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: challengeCtrl,
                    decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'add challenge + Enter',
                        prefixIcon: Icon(Icons.add, size: 18)),
                    onSubmitted: (v) {
                      m.addChallenge(v);
                      challengeCtrl.clear();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceCountsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    final pplCtrl = TextEditingController(text: m.personnelCount.toString());
    final batCtrl = TextEditingController(text: m.spareBatteries.toString());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: pplCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Rescue personnel on the operation'),
                onSubmitted: (v) =>
                    m.setCounts(personnel: int.tryParse(v) ?? m.personnelCount),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: batCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Spare batteries (swap stock)'),
                onSubmitted: (v) =>
                    m.setCounts(batteries: int.tryParse(v) ?? m.spareBatteries),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModulesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Our comm modules',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add module'),
                  onPressed: () => _addModule(context, m),
                ),
              ],
            ),
            if (m.modules.isEmpty)
              const Text('No modules listed. Add each of our units by ID '
                  '(e.g. DCM-A-0042); a module can attach to one drone.')
            else
              ...m.modules.map((mod) {
                final cached = m.productCache.containsKey(mod.unitId);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.memory),
                  title: Text('${mod.label}  (${mod.unitId})'),
                  subtitle: Text([
                    mod.attachedTo.isEmpty
                        ? 'spare stock'
                        : 'attached to ${mod.attachedTo}',
                    if (cached) 'specs cached',
                  ].join('  |  ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'fetch specs (online)',
                        icon: Icon(cached ? Icons.cloud_done : Icons.cloud_download,
                            size: 18),
                        onPressed: () => fetchUnitSpecs(context, m, mod.unitId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => m.removeModule(mod),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _addModule(BuildContext context, MissionState m) async {
    final idCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add comm module'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                  labelText: 'Unit ID', hintText: 'e.g. DCM-A-0042'),
            ),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                  labelText: 'Label', hintText: 'e.g. module B'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final err = m.addModule(ModuleResource(
      unitId: idCtrl.text.trim(),
      label: labelCtrl.text.trim().isEmpty
          ? idCtrl.text.trim()
          : labelCtrl.text.trim(),
    ));
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _DronesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Drones (${m.drones.length})',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add drone'),
                  onPressed: () => _addDrone(context, m),
                ),
              ],
            ),
            Text(
              'Add ours by unit ID, a volunteer drone with one of our '
              'modules attached, or a minimal entry. Works offline too.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            if (m.drones.isEmpty)
              const Text('No drones yet.')
            else
              ...m.drones.map((d) {
                final specs = m.specsFor(d);
                // The unit ID to fetch: the drone's own (brand) or its
                // attached module's (volunteer carrying our module).
                final fetchId =
                    d.unitId.isNotEmpty ? d.unitId : d.attachedModuleId;
                return ListTile(
                  dense: true,
                  leading: Icon(d.source == 'brand'
                      ? Icons.verified
                      : Icons.volunteer_activism),
                  title: Text(d.label),
                  subtitle: Text([
                    if (d.unitId.isNotEmpty) 'unit ${d.unitId}',
                    if (d.makeModel.isNotEmpty) d.makeModel,
                    if (d.owner.isNotEmpty) 'pilot ${d.owner}',
                    if (d.attachedModuleId.isNotEmpty)
                      'module ${d.attachedModuleId}',
                    specs == null
                        ? 'specs unknown'
                        : 'AP ${specs.apRangeM?.toStringAsFixed(0) ?? "?"} m',
                  ].join('  |  ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (fetchId.isNotEmpty)
                        IconButton(
                          tooltip: 'fetch specs (online)',
                          icon: Icon(
                              specs != null
                                  ? Icons.cloud_done
                                  : Icons.cloud_download,
                              size: 18),
                          onPressed: () => fetchUnitSpecs(context, m, fetchId),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => m.removeDrone(d),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _addDrone(BuildContext context, MissionState m) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddDroneDialog(mission: m),
    );
  }
}

class _AddDroneDialog extends StatefulWidget {
  final MissionState mission;

  const _AddDroneDialog({required this.mission});

  @override
  State<_AddDroneDialog> createState() => _AddDroneDialogState();
}

class _AddDroneDialogState extends State<_AddDroneDialog> {
  String _source = 'brand';
  final _label = TextEditingController();
  final _unitId = TextEditingController();
  final _makeModel = TextEditingController();
  final _owner = TextEditingController();
  String? _moduleId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final freeModules = m.modules
        .where((mod) => mod.attachedTo.isEmpty)
        .map((mod) => mod.unitId)
        .toList();
    return AlertDialog(
      title: const Text('Add drone'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'brand', label: Text('Our brand')),
                ButtonSegment(value: 'volunteer', label: Text('Volunteer')),
              ],
              selected: {_source},
              onSelectionChanged: (s) => setState(() => _source = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'Label', hintText: 'e.g. relay-1 or Ann\'s drone'),
            ),
            if (_source == 'brand')
              TextField(
                controller: _unitId,
                decoration: const InputDecoration(
                    labelText: 'Unit ID (fetch specs in the planner)',
                    hintText: 'e.g. DRN-S-0007'),
              )
            else ...[
              TextField(
                controller: _makeModel,
                decoration: const InputDecoration(
                    labelText: 'Make / model', hintText: 'e.g. DJI Mavic'),
              ),
              TextField(
                controller: _owner,
                decoration: const InputDecoration(
                    labelText: 'Owner / pilot', hintText: 'e.g. personABC'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _moduleId,
                decoration: const InputDecoration(
                    labelText: 'Attach one of our modules (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('none')),
                  ...freeModules.map(
                      (id) => DropdownMenuItem(value: id, child: Text(id))),
                ],
                onChanged: (v) => setState(() => _moduleId = v),
              ),
              if (freeModules.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No free modules. Add a module first.',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final d = DroneResource(
              label: _label.text.trim(),
              source: _source,
              unitId: _source == 'brand' ? _unitId.text.trim() : '',
              makeModel: _source == 'volunteer' ? _makeModel.text.trim() : '',
              owner: _source == 'volunteer' ? _owner.text.trim() : '',
              attachedModuleId: _source == 'volunteer' ? (_moduleId ?? '') : '',
            );
            final err = m.addDrone(d);
            if (err != null) {
              setState(() => _error = err);
            } else {
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _DeploymentsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MissionState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Deployments',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AI suggest'),
                  onPressed: () => _runAiAdvisor(context, m),
                ),
              ],
            ),
            Text(
              'A deployment is a set of advisory placements drawn on the Map '
              'tab. Activating one never commands a drone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (m.deployments.isEmpty)
              const Text('None yet. Draw placements on the Map tab, or use '
                  'the AI advisor (Settings) while online.')
            else
              ...m.deployments.map((d) {
                final active = d.name == m.activeDeploymentName;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    active ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: active ? Colors.greenAccent : null,
                  ),
                  title: Row(
                    children: [
                      Text(d.name),
                      const SizedBox(width: 8),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(d.source == 'ai' ? 'AI' : 'manual'),
                      ),
                      if (!d.approved) ...[
                        const SizedBox(width: 4),
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('draft'),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('${d.placements.length} placements'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!active)
                        TextButton(
                            onPressed: () => m.activateDeployment(d.name),
                            child: const Text('Activate')),
                      IconButton(
                        icon: Icon(
                            d.approved ? Icons.check_circle : Icons.check_circle_outline,
                            size: 18,
                            color: d.approved ? Colors.greenAccent : null),
                        tooltip: d.approved ? 'approved' : 'approve',
                        onPressed: () =>
                            m.approveDeployment(d, approved: !d.approved),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => m.removeDeployment(d),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _runAiAdvisor(BuildContext context, MissionState m) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    if (!app.aiConfigured) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Set the AI endpoint and key in Settings first.')));
      return;
    }
    if (m.area.length < 3) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Draw the operation area on the Map tab first.')));
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Asking the AI for a deployment...')),
        ]),
      ),
    );

    final advisor = AiAdvisor(
      endpoint: app.aiEndpoint,
      model: app.aiModel,
      apiKey: app.aiApiKey,
    );
    try {
      final suggestion = await advisor.suggest(m);
      var n = 1;
      while (m.deployments.any((d) => d.name == 'AI plan $n')) {
        n++;
      }
      m.addDeployment(
        Deployment(
          name: 'AI plan $n',
          source: 'ai',
          placements: suggestion.placements,
        ),
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss the loading dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('AI plan $n (draft)'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.summary.isEmpty
                    ? '${suggestion.placements.length} placements proposed. '
                        'Review and edit on the Map, then approve.'
                    : suggestion.summary),
                if (suggestion.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Warnings',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  ...suggestion.warnings.map((w) => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 16, color: Colors.orangeAccent),
                          const SizedBox(width: 6),
                          Expanded(child: Text(w)),
                        ],
                      )),
                ],
                const SizedBox(height: 12),
                Text(
                  'This is a DRAFT: it is now the active deployment on the Map '
                  'so you can edit placements, then tick approve.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Review on map')),
          ],
        ),
      );
    } on AiAdvisorException catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('AI planning failed: $e')));
    } finally {
      advisor.close();
    }
  }
}
