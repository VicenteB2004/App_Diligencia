import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/group_location.dart';
import 'package:notificador/data/services/auth_service.dart';
import 'package:notificador/data/services/firestore_service.dart';

class FirebaseUsageExamples {
  FirebaseUsageExamples({
    AuthService? authService,
    FirestoreService? firestoreService,
  }) : _authService = authService ?? AuthService(),
       _firestoreService = firestoreService ?? FirestoreService();

  final AuthService _authService;
  final FirestoreService _firestoreService;

  Future<AppUser> registerUserExample() async {
    return _authService.registerUser(
      email: 'abogado1@demo.com',
      password: 'Secret123!',
      rol: 'abogado',
      groupId: 'grupo-legal-001',
    );
  }

  Future<void> loginExample() async {
    await _authService.loginUser(
      email: 'abogado1@demo.com',
      password: 'Secret123!',
    );
  }

  Future<String> currentGroupIdExample() async {
    return _firestoreService.getCurrentUserGroupId();
  }

  Future<void> saveLocationExample({
    required double lat,
    required double lng,
  }) async {
    await _firestoreService.saveLocation(lat: lat, lng: lng);
  }

  Future<List<GroupLocation>> filteredLocationsExample() async {
    return _firestoreService.getLocationsByCurrentUserGroup();
  }
}
