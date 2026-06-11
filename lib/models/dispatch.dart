enum DispatchStatus { draft, loaded, inTransit, delivered }

extension DispatchStatusX on DispatchStatus {
  String get label {
    switch (this) {
      case DispatchStatus.draft:
        return 'Draft';
      case DispatchStatus.loaded:
        return 'Loaded';
      case DispatchStatus.inTransit:
        return 'In Transit';
      case DispatchStatus.delivered:
        return 'Delivered';
    }
  }
}

class Dispatch {
  const Dispatch({
    required this.id,
    required this.customerName,
    required this.materialName,
    required this.weightKg,
    required this.vehicleNumber,
    required this.driverName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String customerName;
  final String materialName;
  final double weightKg;
  final String vehicleNumber;
  final String driverName;
  final DispatchStatus status;
  final DateTime createdAt;
}
