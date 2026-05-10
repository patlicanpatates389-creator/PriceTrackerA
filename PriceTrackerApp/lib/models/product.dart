class Product {
  final int? id;
  final String url;
  final String name;
  final double currentPrice;
  final String historyJson; // Stores JSON array of {timestamp: price}

  Product({
    this.id,
    required this.url,
    required this.name,
    required this.currentPrice,
    required this.historyJson,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'name': name,
      'currentPrice': currentPrice,
      'historyJson': historyJson,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      url: map['url'],
      name: map['name'],
      currentPrice: map['currentPrice'],
      historyJson: map['historyJson'],
    );
  }
}
