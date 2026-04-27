import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Collections ──────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');

  CollectionReference<Map<String, dynamic>> _batches(String productId) =>
      _products.doc(productId).collection('batches');

  CollectionReference<Map<String, dynamic>> get _poTracker =>
      _db.collection('po_tracker');

  // ─── Products ─────────────────────────────────────────────────────────────

  Future<void> upsertProduct(OdooProduct product) async {
    await _products.doc(product.firestoreId).set(
      product.toFirestore(),
      SetOptions(merge: true),
    );
  }

  Future<void> upsertProducts(List<OdooProduct> products) async {
    final batch = _db.batch();
    for (final p in products) {
      batch.set(
        _products.doc(p.firestoreId),
        p.toFirestore(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Stream<List<OdooProduct>> streamProducts() {
    return _products
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => OdooProduct.fromFirestore(d.id, d.data()))
        .toList());
  }

  // ─── Batches ──────────────────────────────────────────────────────────────

  Future<String> addBatch(String productId, BatchModel batch) async {
    final doc = await _batches(productId).add(batch.toFirestore());
    return doc.id;
  }

  Future<void> updateBatch(
      String productId, String batchId, Map<String, dynamic> fields) async {
    await _batches(productId).doc(batchId).update(fields);
  }

  Future<void> deleteBatch(String productId, String batchId) async {
    await _batches(productId).doc(batchId).delete();
  }

  Stream<List<BatchModel>> streamBatches(String productId) {
    return _batches(productId)
        .orderBy('expiryDate') // FEFO: soonest first
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => BatchModel.fromFirestore(d.id, d.data()))
        .toList());
  }

  /// All batches expiring within [days] days (for dashboard & notifications)
  Future<List<ExpiringBatch>> fetchExpiringBatches({int days = 7}) async {
    final threshold =
    Timestamp.fromDate(DateTime.now().add(Duration(days: days)));
    final now = Timestamp.fromDate(DateTime.now());

    final products = await _products.get();
    final results = <ExpiringBatch>[];

    for (final productDoc in products.docs) {
      final productName = productDoc.data()['name'] as String? ?? '';

      final batches = await _batches(productDoc.id)
          .where('expiryDate', isGreaterThanOrEqualTo: now)
          .where('expiryDate', isLessThanOrEqualTo: threshold)
          .orderBy('expiryDate')
          .get();

      for (final b in batches.docs) {
        results.add(ExpiringBatch(
          productId: productDoc.id,
          productName: productName,
          batch: BatchModel.fromFirestore(b.id, b.data()),
        ));
      }
    }

    // Sort globally by soonest expiry
    results.sort((a, b) =>
        a.batch.expiryDate.compareTo(b.batch.expiryDate));

    return results;
  }

  // ─── PO Tracker ───────────────────────────────────────────────────────────

  Future<List<int>> getTrackedPoIds() async {
    final doc = await _poTracker.doc('seen_ids').get();
    if (!doc.exists) return [];
    return List<int>.from(doc.data()?['ids'] ?? []);
  }

  Future<void> markPoAsSeen(List<int> ids) async {
    final existing = await getTrackedPoIds();
    final merged = {...existing, ...ids}.toList();
    await _poTracker.doc('seen_ids').set({'ids': merged});
  }
}

class ExpiringBatch {
  final String productId;
  final String productName;
  final BatchModel batch;

  ExpiringBatch({
    required this.productId,
    required this.productName,
    required this.batch,
  });

  int get daysLeft =>
      batch.expiryDate.difference(DateTime.now()).inDays;
}