import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../hw_accent.dart';
import '../hw_widgets.dart';
import '../hw_native_bridge.dart';

class BatteryInfoScreen extends StatefulWidget {
  const BatteryInfoScreen({super.key});

  @override
  State<BatteryInfoScreen> createState() => _BatteryInfoScreenState();
}

class _BatteryInfoScreenState extends State<BatteryInfoScreen> {
  int _level = 0;
  String _state = 'Unknown';
  String _powerSource = 'Internal Battery Power';
  bool _lowPowerMode = false;
  String _thermalState = 'Normal';
  List<Map<String, dynamic>> _accessories = const [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final data = await HwNativeBridge.getBatteryAndAccessories();
    if (!mounted) return;
    final rawAcc = (data['accessories'] as List?) ?? const [];
    setState(() {
      _level = (data['level'] as num?)?.toInt() ?? 0;
      _state = (data['state'] as String?) ?? 'Unknown';
      _powerSource = (data['powerSource'] as String?) ?? 'Internal Battery Power';
      _lowPowerMode = data['lowPowerMode'] == true;
      _thermalState = (data['thermalState'] as String?) ?? 'Normal';
      _accessories = rawAcc.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = HwAccent.instance.resolvedAccent(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    final levelColor = _level <= 20 ? red : (_level <= 50 ? orange : green);
    final thermalColor = _thermalState == 'Normal'
        ? green
        : (_thermalState == 'Fair' ? orange : red);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Battery & BT Info'),
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: _refresh,
          child: const Icon(CupertinoIcons.refresh, size: 20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary Device Battery Card
                    HwCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: levelColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _state == 'Charging'
                                      ? CupertinoIcons.battery_charging
                                      : CupertinoIcons.battery_full,
                                  size: 26,
                                  color: levelColor,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Internal Battery',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$_state · $_powerSource',
                                      style: TextStyle(fontSize: 13, color: secondary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '$_level%',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: levelColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Progress bar
                          Container(
                            height: 10,
                            width: double.infinity,
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: hwLabel(context, 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FractionallySizedBox(
                              widthFactor: (_level / 100.0).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: levelColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _infoRow(context, 'Charging State', _state, accent),
                          _divider(context),
                          _infoRow(
                            context,
                            'Battery Saver Mode',
                            _lowPowerMode ? 'Enabled' : 'Off',
                            _lowPowerMode ? orange : secondary,
                          ),
                          _divider(context),
                          _infoRow(context, 'Thermal State', _thermalState, thermalColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.only(left: 32, bottom: 12),
                      child: Text(
                        'CONNECTED BLUETOOTH ACCESSORIES',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: secondary,
                        ),
                      ),
                    ),
                    if (_accessories.isEmpty)
                      HwCard(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.bluetooth, size: 22, color: secondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No active Bluetooth audio or peripheral accessories connected.',
                                style: TextStyle(fontSize: 14, color: secondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      HwCard(
                        child: Column(
                          children: [
                            for (var i = 0; i < _accessories.length; i++) ...[
                              _accessoryRow(context, _accessories[i], accent, green),
                              if (i != _accessories.length - 1) _divider(context),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Single Done button matching BatteryInfoViewController.swift
            Container(
              color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(height: 0.5, color: hwLabel(context, 0.06));

  Widget _infoRow(BuildContext context, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }

  Widget _accessoryRow(
    BuildContext context,
    Map<String, dynamic> acc,
    Color accent,
    Color green,
  ) {
    final name = (acc['name'] as String?) ?? 'Bluetooth Device';
    final bat = acc['batteryLevel'] as int?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(CupertinoIcons.headphones, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Connected',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: green),
                ),
              ],
            ),
          ),
          if (bat != null)
            HwStatusPill(
              icon: CupertinoIcons.battery_75_percent,
              text: '$bat%',
              color: green,
              active: true,
            ),
        ],
      ),
    );
  }
}