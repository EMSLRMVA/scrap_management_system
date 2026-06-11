import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class DynamicPageDataService {
  DynamicPageDataService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> watchCollection(String collection) {
    if (!isAvailable || collection.trim().isEmpty) {
      return const Stream.empty();
    }
    return _firestore
        .collection(collection.trim())
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> saveEntry(String collection, Map<String, dynamic> values) async {
    if (!isAvailable || collection.trim().isEmpty) {
      return;
    }
    await _firestore.collection(collection.trim()).add({
      ...values,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEntry(String collection, String id) async {
    if (!isAvailable || collection.trim().isEmpty || id.isEmpty) {
      return;
    }
    await _firestore.collection(collection.trim()).doc(id).delete();
  }
}
