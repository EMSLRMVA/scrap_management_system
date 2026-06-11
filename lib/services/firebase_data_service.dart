import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseDataService {
  FirebaseDataService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _firestore.collection(path);
  }

  Future<void> upsert({
    required String collectionPath,
    required String documentId,
    required Map<String, Object?> data,
  }) {
    return collection(
      collectionPath,
    ).doc(documentId).set(data, SetOptions(merge: true));
  }

  Future<void> delete({
    required String collectionPath,
    required String documentId,
  }) {
    return collection(collectionPath).doc(documentId).delete();
  }
}
