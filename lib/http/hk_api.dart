import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';

abstract final class HkApi {
  static const String _allowFallbackKey = 'allowHkFallback';
  static const String _hasRetriedKey = 'hasRetriedWithHk';
  static const String _healthPath = '/x/click-interface/click/now';

  static bool get isConfigured => Pref.apiHKUrl.isNotEmpty;
  static String get baseUrl => Pref.apiHKUrl;

  static Options withFallback([Options? options]) {
    return (options ?? Options()).copyWith(
      extra: {
        ...?options?.extra,
        _allowFallbackKey: true,
      },
    );
  }

  static bool canFallback(RequestOptions options) {
    return isConfigured &&
        options.method == 'GET' &&
        options.extra[_allowFallbackKey] == true &&
        options.extra[_hasRetriedKey] != true &&
        options.baseUrl != baseUrl;
  }

  static Map<String, dynamic> retriedExtra(RequestOptions options) {
    return {
      ...options.extra,
      _allowFallbackKey: true,
      _hasRetriedKey: true,
    };
  }

  static Future<HkApiCheckResult> check(String baseUrl) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio.get(_healthPath);
      stopwatch.stop();
      final data = response.data;
      final serverNow = data is Map
          ? _parseTimestamp(data['data']?['now'])
          : null;
      if (data is Map && data['code'] == 0 && serverNow != null) {
        return HkApiCheckResult(
          available: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          serverTimestamp: serverNow,
          message: '可用',
        );
      }
      return HkApiCheckResult(
        available: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: data is Map && data['message'] != null
            ? data['message'].toString()
            : '响应格式异常',
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return HkApiCheckResult(
        available: false,
        latencyMs: stopwatch.elapsedMilliseconds == 0
            ? null
            : stopwatch.elapsedMilliseconds,
        message: e.message ?? '连接失败',
      );
    } finally {
      dio.close(force: true);
    }
  }

  static int? _parseTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

final class HkApiCheckResult {
  const HkApiCheckResult({
    required this.available,
    required this.message,
    this.latencyMs,
    this.serverTimestamp,
  });

  final bool available;
  final String message;
  final int? latencyMs;
  final int? serverTimestamp;
}

class HkApiRetryInterceptor extends Interceptor {
  HkApiRetryInterceptor(this.client);

  final Dio client;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final originalOptions = response.requestOptions;
    if (!HkApi.canFallback(originalOptions)) {
      return handler.next(response);
    }

    final data = response.data;
    if (data is! Map || (data['code'] != -404 && data['code'] != -10403)) {
      return handler.next(response);
    }

    _retryWithHk(originalOptions, response, handler);
  }

  Future<void> _retryWithHk(
    RequestOptions originalOptions,
    Response originalResponse,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      final newResponse = await client.fetch(
        originalOptions.copyWith(
          baseUrl: HkApi.baseUrl,
          extra: HkApi.retriedExtra(originalOptions),
          headers: Map<String, dynamic>.from(originalOptions.headers),
          queryParameters: Map<String, dynamic>.from(
            originalOptions.queryParameters,
          ),
          data: originalOptions.data,
          cancelToken: originalOptions.cancelToken,
        ),
      );
      handler.resolve(newResponse);
    } on DioException {
      handler.next(originalResponse);
    }
  }
}
