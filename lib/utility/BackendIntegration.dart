import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class BackendIntegration {
  final String baseUrl;
  final http.Client _httpClient;

  BackendIntegration({
    // Updated to your new Elastic Beanstalk URL
    this.baseUrl = 'http://intrst-backend.us-east-1.elasticbeanstalk.com',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  // Your curl command didn't show an Auth header,
  // so we only need Content-Type now.
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> createResponse({
    required String model,
    required String input,
  }) async {
    // Updated endpoint to /generate
    final uri = Uri.parse('$baseUrl/generate');

    final body = {
      'model': model,
      'input': input,
    };

    final response = await _httpClient.post(
      uri,
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw HttpException(
        'Backend error (${response.statusCode}): ${response.body}',
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }

  /// New simplified parser for: {"text": "[\"item1\", \"item2\"]"}
  List<String> extractAutocompleteEntries(Map<String, dynamic> response) {
    final String? textOutput = response['text'];

    if (textOutput == null || textOutput.isEmpty) return [];

    try {
      // The backend returns a stringified JSON array, so we parse it again
      // We also clean up any potential markdown artifacts just in case
      String cleanedText = textOutput.replaceAll(RegExp(r'^```json\s*|```$'), '').trim();

      final List<dynamic> decodedList = jsonDecode(cleanedText);
      return decodedList.map((item) => item.toString()).toList();
    } catch (e) {
      // If parsing fails, return an empty list or handle as needed
      return [];
    }
  }
}