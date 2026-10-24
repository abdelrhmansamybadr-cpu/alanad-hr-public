import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/models/json.dart';

/// One person of a meeting.
class MeetingPerson {
  final int userId;
  final String name;
  final String role; // host | member
  final bool joined; // in the call right now
  final bool removed;
  const MeetingPerson({required this.userId, required this.name, required this.role, required this.joined, required this.removed});

  bool get isHost => role == 'host';

  factory MeetingPerson.fromJson(Map<String, dynamic> m) =>
      MeetingPerson(userId: jInt(m, 'userId'), name: jStr(m, 'name'), role: jStr(m, 'role', 'member'), joined: jBool(m, 'joined'), removed: jBool(m, 'removed'));
}

class Meeting {
  final int id;
  final String title;
  final String? notes;
  final DateTime scheduledAt; // local time
  final int durationMin;
  final String status; // scheduled | live | ended | cancelled
  final int createdBy;
  final List<MeetingPerson> people;
  final bool canJoin;

  const Meeting({required this.id, required this.title, this.notes, required this.scheduledAt, required this.durationMin, required this.status, required this.createdBy, required this.people, required this.canJoin});

  bool get isLive => status == 'live';
  bool get isOver => status == 'ended' || status == 'cancelled';
  List<MeetingPerson> get active => people.where((p) => !p.removed).toList();
  int get inCall => people.where((p) => p.joined && !p.removed).length;

  factory Meeting.fromJson(Map<String, dynamic> m) => Meeting(
        id: jInt(m, 'id'),
        title: jStr(m, 'title'),
        notes: jStrN(m, 'notes'),
        scheduledAt: (DateTime.tryParse(jStr(m, 'scheduledAt')) ?? DateTime.now()).toLocal(),
        durationMin: jInt(m, 'durationMin', 30),
        status: jStr(m, 'status', 'scheduled'),
        createdBy: jInt(m, 'createdBy'),
        people: asMapList(m['participants']).map(MeetingPerson.fromJson).toList(),
        canJoin: jBool(m, 'canJoin'),
      );
}

/// Someone the signed-in person may invite.
class Invitee {
  final int id;
  final String name;
  final String role;
  const Invitee({required this.id, required this.name, required this.role});
  factory Invitee.fromJson(Map<String, dynamic> m) => Invitee(id: jInt(m, 'id'), name: jStr(m, 'name'), role: jStr(m, 'role'));
}

class MeetingsBootstrap {
  final bool canSchedule;
  final List<Invitee> invitable;
  const MeetingsBootstrap({required this.canSchedule, required this.invitable});
  factory MeetingsBootstrap.fromJson(Map<String, dynamic> m) =>
      MeetingsBootstrap(canSchedule: jBool(m, 'canSchedule'), invitable: asMapList(m['invitable']).map(Invitee.fromJson).toList());
}

/// My meetings (upcoming and the last two weeks).
final meetingsListProvider = FutureProvider.autoDispose<List<Meeting>>((ref) async {
  final data = await ref.read(apiProvider).get('/meetings');
  return data is List ? data.whereType<Map>().map((e) => Meeting.fromJson(asMap(e))).toList() : <Meeting>[];
});

final meetingsBootstrapProvider = FutureProvider.autoDispose<MeetingsBootstrap>((ref) async => MeetingsBootstrap.fromJson(asMap(await ref.read(apiProvider).get('/meetings/bootstrap'))));

final meetingProvider = FutureProvider.autoDispose.family<Meeting, int>((ref, id) async => Meeting.fromJson(asMap(await ref.read(apiProvider).get('/meetings/$id'))));
