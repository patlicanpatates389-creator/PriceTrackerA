import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:fl_chart/fl_chart.dart';

import 'models/product.dart';
import 'services/database_service.dart';
import 'services/scraper_service.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await NotificationService.initialize();
      final products = await DatabaseService.instance.readAllProducts();
      
      for (var product in products) {
        final newPrice = await ScraperService.fetchPrice(product.url);
        if (newPrice != null && newPrice != product.currentPrice) {
          
          // Send notification
          String direction = newPrice < product.currentPrice ? "dropped to" : "increased to";
          await NotificationService.showNotification(
            id: product.id ?? 0,
            title: "Price Update: \${product.name}",
            body: "The price has \$direction \$\${newPrice.toStringAsFixed(2)}",
          );

          // Update DB
          Map<String, dynamic> history = jsonDecode(product.historyJson);
          history[DateTime.now().toIso8601String()] = newPrice;
          
          Product updatedProduct = Product(
            id: product.id,
            url: product.url,
            name: product.name,
            currentPrice: newPrice,
            historyJson: jsonEncode(history),
          );
          
          await DatabaseService.instance.update(updatedProduct);
        }
      }
    } catch (e) {
      print("Background task error: \$e");
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid || Platform.isIOS) {
    await NotificationService.initialize();
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    Workmanager().registerPeriodicTask(
      "price-tracker-task",
      "checkPrices",
      frequency: const Duration(hours: 1),
    );
  }

  runApp(const PriceTrackerApp());
}

class PriceTrackerApp extends StatelessWidget {
  const PriceTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Price Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> products = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => isLoading = true);
    products = await DatabaseService.instance.readAllProducts();
    setState(() => isLoading = false);
  }

  void _showAddDialog() {
    final TextEditingController urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Product to Track'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(hintText: "Enter Product URL"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              String url = urlController.text;
              if (url.isNotEmpty) {
                Navigator.pop(context);
                await _addProduct(url);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(String url) async {
    setState(() => isLoading = true);
    
    String title = await ScraperService.fetchTitle(url);
    double? price = await ScraperService.fetchPrice(url);
    
    if (price != null) {
      Map<String, dynamic> initialHistory = {
        DateTime.now().toIso8601String(): price,
      };
      
      Product newProduct = Product(
        url: url,
        name: title,
        currentPrice: price,
        historyJson: jsonEncode(initialHistory),
      );
      
      await DatabaseService.instance.create(newProduct);
      await _loadProducts();
    } else {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find price on that page.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Price Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Trigger a manual refresh of all prices
            },
          )
        ],
      ),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator())
          : products.isEmpty 
              ? const Center(child: Text("No products tracked yet."))
              : ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final p = products[index];
                    return ListTile(
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text("Current Price: \$\${p.currentPrice.toStringAsFixed(2)}"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductDetailScreen(product: p),
                          ),
                        ).then((_) => _loadProducts());
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ProductDetailScreen extends StatelessWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> history = jsonDecode(product.historyJson);
    
    // Sort chronologically
    var sortedKeys = history.keys.toList()..sort();
    
    List<FlSpot> spots = [];
    double minPrice = double.infinity;
    double maxPrice = 0;
    
    for (int i = 0; i < sortedKeys.length; i++) {
      double price = (history[sortedKeys[i]] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), price));
      if (price < minPrice) minPrice = price;
      if (price > maxPrice) maxPrice = price;
    }
    
    // Provide some padding to the chart bounds
    if (minPrice == double.infinity) minPrice = 0;
    minPrice = minPrice * 0.9;
    maxPrice = maxPrice * 1.1;
    if (maxPrice == 0) maxPrice = 10;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Details"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              await DatabaseService.instance.delete(product.id!);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("Current: \$\${product.currentPrice.toStringAsFixed(2)}", style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.greenAccent)),
            const SizedBox(height: 32),
            const Text("Price History"),
            const SizedBox(height: 16),
            Expanded(
              child: spots.length < 2 
                ? const Center(child: Text("Not enough data points for chart. Check back later!"))
                : LineChart(
                  LineChartData(
                    minY: minPrice,
                    maxY: maxPrice,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: Colors.deepPurpleAccent,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.deepPurpleAccent.withOpacity(0.3),
                        ),
                      ),
                    ],
                    titlesData: const FlTitlesData(
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), // Hide bottom text for simplicity
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}
