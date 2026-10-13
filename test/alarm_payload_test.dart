import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_reminder_app/services/notifications.dart';

void main() {
  test('alarm payload survives serialization for reboot-restored notification', () {
    const AlarmPayload input = AlarmPayload(
      medicineId: 42,
      patientId: 7,
      scheduledAt: 1791928800000,
      notificationId: 101,
    );
    final AlarmPayload? output = AlarmPayload.decode(input.encode());
    expect(output, isNotNull);
    expect(output!.medicineId, input.medicineId);
    expect(output.patientId, input.patientId);
    expect(output.scheduledAt, input.scheduledAt);
    expect(output.notificationId, input.notificationId);
    expect(AlarmPayload.decode('{invalid'), isNull);
  });
}
