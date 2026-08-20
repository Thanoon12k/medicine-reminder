import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/jar.dart';
import '../widgets/pill_art.dart';

class JarScreen extends StatefulWidget {
  const JarScreen({super.key});

  @override
  State<JarScreen> createState() => _JarScreenState();
}

class _JarScreenState extends State<JarScreen> {
  /// null = عرض كل الحبوب.
  DateTime? _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) {
        final List<DoseLog> logs = appState.takenLogs(month: _month);
        final Map<String, List<DoseLog>> byDay = <String, List<DoseLog>>{};
        for (final DoseLog l in logs.reversed) {
          final DateTime d = l.takenTime;
          final String key = Fmt.storeDate(d);
          byDay.putIfAbsent(key, () => <DoseLog>[]).add(l);
        }

        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('العلبة'),
              actions: <Widget>[
                IconButton(
                  iconSize: 26,
                  tooltip: _month == null ? 'عرض شهر' : 'عرض الكل',
                  icon: Icon(
                    _month == null
                        ? Icons.calendar_month_outlined
                        : Icons.all_inclusive,
                  ),
                  onPressed: () => setState(() {
                    _month = _month == null
                        ? DateTime(DateTime.now().year, DateTime.now().month)
                        : null;
                  }),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: <Widget>[
                  if (_month != null) _monthBar(),
                  const SizedBox(height: 10),
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: 340,
                          child: JarView(
                            pills: logs
                                .map(
                                  (DoseLog l) => JarPill(l.form, l.colorIndex),
                                )
                                .toList(),
                            dropSignal: appState.lastDropKey,
                            maxDrawn: 220,
                            emptyText: _month == null
                                ? 'العلبة فارغة\nكل حبة تأخذها ستنزل هنا'
                                : 'لا توجد حبوب في هذا الشهر',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${Fmt.n(logs.length)} حبة في العلبة',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (byDay.isNotEmpty) const SectionTitle('السجل'),
                  ...byDay.entries.map(
                    (MapEntry<String, List<DoseLog>> e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DayGroup(
                        day: Fmt.parseDate(e.key),
                        logs: e.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _monthBar() {
    final DateTime m = _month!;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: <Widget>[
          IconButton(
            iconSize: 30,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
              () => _month = DateTime(m.year, m.month - 1),
            ),
          ),
          Expanded(
            child: Text(
              '${Fmt.monthNames[m.month - 1]} ${Fmt.n(m.year)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            iconSize: 30,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _month = DateTime(m.year, m.month + 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.day, required this.logs});

  final DateTime day;
  final List<DoseLog> logs;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                Fmt.relativeDay(day),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${Fmt.n(logs.length)} حبة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...logs.map(
            (DoseLog l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  PillIcon(form: l.form, colorIndex: l.colorIndex, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.medName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    Fmt.timeOf(l.takenTime),
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
