import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';

class JRSTrackingService {
  static final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Track JRS package by tracking ID
  static Future<JRSTrackingResult> trackPackage(String trackingId) async {
    try {
      AppLogger.d('Tracking JRS package: $trackingId');

      // Get current user token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await user.getIdToken();

      // Prepare request data
      final requestData = {
        'trackingId': trackingId.trim(),
      };

      AppLogger.d('JRS tracking request data: $requestData');

      // Call the Firebase function
      final callable = _functions.httpsCallable('trackJRSShipping');
      
      final result = await callable.call(requestData);
      final data = result.data;

      AppLogger.d('JRS tracking raw response: $data');
      AppLogger.d('JRS tracking response type: ${data.runtimeType}');

      // Handle the response data with proper type casting
      if (data is Map) {
        final responseMap = Map<String, dynamic>.from(data);
        
        if (responseMap['success'] == true) {
          final trackingDataRaw = responseMap['data'];
          
          if (trackingDataRaw != null) {
            // Safely cast the tracking data
            final trackingData = trackingDataRaw is Map 
                ? Map<String, dynamic>.from(trackingDataRaw)
                : <String, dynamic>{};
            
            // Safely extract events
            final eventsRaw = trackingData['events'];
            final events = <TrackingEvent>[];
            
            if (eventsRaw is List) {
              for (var eventItem in eventsRaw) {
                if (eventItem is Map) {
                  final eventMap = Map<String, dynamic>.from(eventItem);
                  events.add(TrackingEvent.fromMap(eventMap));
                }
              }
            }
            
            return JRSTrackingResult(
              success: true,
              trackingId: trackingData['trackingId']?.toString() ?? trackingId,
              status: trackingData['status']?.toString() ?? 'Unknown',
              location: trackingData['location']?.toString(),
              timestamp: trackingData['timestamp']?.toString(),
              events: events,
              message: 'Package tracking retrieved successfully',
            );
          } else {
            return JRSTrackingResult(
              success: false,
              trackingId: trackingId,
              status: 'Unknown',
              message: 'No tracking data available',
              error: 'Empty response data',
              events: [],
            );
          }
        } else {
          final errorMessage = responseMap['error']?.toString() 
              ?? responseMap['message']?.toString() 
              ?? 'Failed to track package';
          AppLogger.d('JRS tracking failed: $errorMessage');
          
          return JRSTrackingResult(
            success: false,
            trackingId: trackingId,
            status: 'Unknown',
            message: errorMessage,
            error: errorMessage,
            events: [],
          );
        }
      } else {
        throw Exception('Invalid response format from tracking service');
      }

    } catch (e) {
      AppLogger.d('JRS tracking error: $e');
      
      return JRSTrackingResult(
        success: false,
        trackingId: trackingId,
        status: 'Error',
        message: 'Failed to track package',
        error: e.toString(),
        events: [],
      );
    }
  }

  /// Test the JRS tracking service connection
  static Future<JRSTrackingResult> testTracking() async {
    return await trackPackage('TEST123456789');
  }
}

/// Result class for JRS tracking
class JRSTrackingResult {
  final bool success;
  final String trackingId;
  final String status;
  final String? location;
  final String? timestamp;
  final List<TrackingEvent> events;
  final String message;
  final String? error;

  JRSTrackingResult({
    required this.success,
    required this.trackingId,
    required this.status,
    this.location,
    this.timestamp,
    required this.events,
    required this.message,
    this.error,
  });

  @override
  String toString() {
    return 'JRSTrackingResult{success: $success, trackingId: $trackingId, status: $status, location: $location, message: $message}';
  }
}

/// Tracking event class
class TrackingEvent {
  final String status;
  final String location;
  final String timestamp;
  final String? description;

  TrackingEvent({
    required this.status,
    required this.location,
    required this.timestamp,
    this.description,
  });

  factory TrackingEvent.fromMap(Map<String, dynamic> map) {
    return TrackingEvent(
      status: map['status'] ?? 'Unknown',
      location: map['location'] ?? 'Unknown',
      timestamp: map['timestamp'] ?? '',
      description: map['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'location': location,
      'timestamp': timestamp,
      'description': description,
    };
  }
}
