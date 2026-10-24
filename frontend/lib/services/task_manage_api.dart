
import 'dart:convert';
import 'package:http/http.dart' as http;

class TaskManageApi {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  static const int userId = int.fromEnvironment(
    'USER_ID',
    defaultValue: 1,
  );

  static Uri taskUri(int taskId) {
    return Uri.parse(
      '$baseUrl/tasks/$taskId',
    ).replace(
      queryParameters: {
        'userId': userId.toString(),
      },
    );
  }

  static Map<String, dynamic> parseResponse(
      http.Response response,
      ) {
    final json = jsonDecode(
      utf8.decode(response.bodyBytes),
    ) as Map<String, dynamic>;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json['code'] != 200) {
      throw Exception(
        json['message'] ?? '任务操作失败',
      );
    }

    return json;
  }

  static Future<Map<String, dynamic>> getTask(
      int taskId,
      ) async {
    final response = await http.get(taskUri(taskId));

    final result = parseResponse(response);

    return Map<String, dynamic>.from(
      result['data'] as Map,
    );
  }

  static Future<void> updateTask(
      int taskId,
      Map<String, dynamic> request,
      ) async {
    final response = await http.put(
      taskUri(taskId),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(request),
    );

    parseResponse(response);
  }

  static Future<void> archiveTask(
      int taskId,
      ) async {
    final response = await http.delete(
      taskUri(taskId),
    );

    parseResponse(response);
  }
}
