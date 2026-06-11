enum PartyType { seller, customer }

extension PartyTypeX on PartyType {
  String get label => this == PartyType.seller ? 'Seller' : 'Customer';
}

class Party {
  const Party({
    required this.id,
    required this.name,
    required this.phone,
    required this.area,
    required this.type,
    this.gstNumber,
    this.address,
    this.openingBalance = 0,
  });

  final String id;
  final String name;
  final String phone;
  final String area;
  final PartyType type;
  final String? gstNumber;
  final String? address;
  final double openingBalance;

  Party copyWith({
    String? id,
    String? name,
    String? phone,
    String? area,
    PartyType? type,
    String? gstNumber,
    String? address,
    double? openingBalance,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      area: area ?? this.area,
      type: type ?? this.type,
      gstNumber: gstNumber ?? this.gstNumber,
      address: address ?? this.address,
      openingBalance: openingBalance ?? this.openingBalance,
    );
  }
}
