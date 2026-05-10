import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'dart:developer' as developer;

class ScraperService {
  static Future<double?> fetchPrice(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      });

      if (response.statusCode == 200) {
        var document = parse(response.body);
        
        // Priority 1: Check for standard schema.org microdata (Product -> price)
        var priceMeta = document.querySelector('meta[itemprop="price"]');
        if (priceMeta != null && priceMeta.attributes['content'] != null) {
          return double.tryParse(priceMeta.attributes['content']!.replaceAll(RegExp(r'[^0-9.]'), ''));
        }
        
        // Priority 2: Check OpenGraph or specific common meta tags
        var ogPrice = document.querySelector('meta[property="product:price:amount"]');
        if (ogPrice != null && ogPrice.attributes['content'] != null) {
          return double.tryParse(ogPrice.attributes['content']!.replaceAll(RegExp(r'[^0-9.]'), ''));
        }

        // Priority 3: Fallback generic regex over the body text to find things like $1,234.56
        // This is very naive but works for a generic fallback.
        String bodyText = document.body?.text ?? '';
        RegExp regex = RegExp(r'\$\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)');
        var match = regex.firstMatch(bodyText);
        if (match != null) {
          String priceString = match.group(1)!.replaceAll(',', '');
          return double.tryParse(priceString);
        }
        
      }
    } catch (e) {
      developer.log("Error fetching price: \$e");
    }
    return null;
  }

  static Future<String> fetchTitle(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0',
      });

      if (response.statusCode == 200) {
        var document = parse(response.body);
        return document.querySelector('title')?.text.trim() ?? 'Unknown Product';
      }
    } catch (e) {
      developer.log("Error fetching title: \$e");
    }
    return 'Unknown Product';
  }
}
