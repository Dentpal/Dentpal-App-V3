
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import axios from 'axios';

// JRS API Configuration - using Firebase secrets

interface TrackJRSRequest {
  trackingId: string;
}

interface JRSTrackingResponse {
  success: boolean;
  data?: {
    trackingId: string;
    status: string;
    location?: string;
    timestamp?: string;
    events?: Array<{
      status: string;
      location: string;
      timestamp: string;
      description?: string;
    }>;
  };
  error?: string;
  message?: string;
}

const verifyAuthToken = async (authorizationHeader: string | undefined): Promise<DecodedIdToken> => {
  if (!authorizationHeader) {
    throw new Error("Missing Authorization header");
  }

  const token = authorizationHeader.startsWith("Bearer ") 
    ? authorizationHeader.substring(7) 
    : authorizationHeader;

  if (!token) {
    throw new Error("Invalid Authorization header format");
  }

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    return decodedToken;
  } catch (error) {
    logger.error("Token verification failed", { error });
    throw new Error("Invalid or expired authentication token");
  }
};

/**
 * Track JRS package by tracking ID
 */
export const trackJRSShipping = onCall(
  { 
    region: 'asia-southeast1',
    cors: true,
    enforceAppCheck: false,
    secrets: ['JRS_API_KEY', 'JRS_TRACKING_API_URL']
  },
  async (request: CallableRequest<TrackJRSRequest>): Promise<JRSTrackingResponse> => {
    try {
      logger.info('JRS tracking request started', { 
        trackingId: request.data.trackingId,
        userId: request.auth?.uid
      });

      // Verify authentication
      const authHeader = request.rawRequest.headers.authorization;
      await verifyAuthToken(authHeader);

      // Validate request data
      if (!request.data.trackingId) {
        logger.error('Invalid request: missing tracking ID');
        throw new HttpsError('invalid-argument', 'Tracking ID is required');
      }

      const trackingId = request.data.trackingId.trim();
      if (trackingId.length === 0) {
        logger.error('Invalid request: empty tracking ID');
        throw new HttpsError('invalid-argument', 'Valid tracking ID is required');
      }

      const trackingApiUrl = process.env.JRS_TRACKING_API_URL || "https://jrs-express.azure-api.net/qa-jrs-tracking-api/api/TrackMyPackage";

      logger.info('Calling JRS tracking API', { 
        url: `${trackingApiUrl}?TrackingID=${trackingId}`,
        trackingId
      });

      // Call JRS tracking API
      const response = await axios.get(`${trackingApiUrl}?TrackingID=${trackingId}`, {
        headers: {
          'Cache-Control': 'no-cache',
          'Ocp-Apim-Subscription-Key': process.env.JRS_API_KEY
        },
        timeout: 30000 // 30 seconds timeout
      });

      logger.info('JRS tracking API response received', { 
        status: response.status,
        statusText: response.statusText,
        data: response.data
      });

      if (response.status === 200 && response.data) {
        // Parse the JRS tracking response
        const trackingData = parseJRSTrackingResponse(response.data, trackingId);
        
        return {
          success: true,
          data: trackingData
        };
      } else {
        logger.error('JRS API returned non-200 status', { 
          status: response.status,
          statusText: response.statusText
        });
        
        return {
          success: false,
          error: `JRS API returned status ${response.status}: ${response.statusText}`,
          message: 'Failed to track package'
        };
      }

    } catch (error: any) {
      logger.error('Error tracking JRS package', { 
        error: error.message || error,
        trackingId: request.data?.trackingId
      });
      
      if (error.code) {
        throw error; // Re-throw HttpsError
      }
      
      return {
        success: false,
        error: error.message || 'Failed to track package',
        message: 'An error occurred while tracking the package'
      };
    }
  }
);

/**
 * Parse JRS tracking API response into our standard format
 */
function parseJRSTrackingResponse(responseData: any, trackingId: string): any {
  try {
    logger.info('Parsing JRS tracking response', { 
      responseType: typeof responseData,
      responseKeys: Object.keys(responseData || {}),
      trackingId
    });

    // JRS API might return different response structures
    // Adapt this based on actual JRS tracking API response format
    
    if (responseData.trackingDetails || responseData.TrackingDetails) {
      const details = responseData.trackingDetails || responseData.TrackingDetails;
      
      return {
        trackingId: trackingId,
        status: details.status || details.Status || 'Unknown',
        location: details.location || details.Location,
        timestamp: details.timestamp || details.Timestamp || details.lastUpdate,
        events: parseTrackingEvents(details.events || details.Events || details.history)
      };
    }
    
    // If response has a different structure, try to extract basic info
    if (responseData.status || responseData.Status) {
      return {
        trackingId: trackingId,
        status: responseData.status || responseData.Status,
        location: responseData.location || responseData.Location,
        timestamp: responseData.timestamp || responseData.Timestamp,
        events: parseTrackingEvents(responseData.events || responseData.Events)
      };
    }

    // If no standard structure found, return raw data with basic info
    logger.warn('Unknown JRS tracking response structure', { responseData });
    
    return {
      trackingId: trackingId,
      status: 'In Transit',
      location: 'Unknown',
      timestamp: new Date().toISOString(),
      events: []
    };

  } catch (error) {
    logger.error('Error parsing JRS tracking response', { 
      error: error instanceof Error ? error.message : String(error),
      responseData,
      trackingId
    });
    
    // Return fallback data
    return {
      trackingId: trackingId,
      status: 'Tracking Information Unavailable',
      location: 'Unknown',
      timestamp: new Date().toISOString(),
      events: []
    };
  }
}

/**
 * Parse tracking events from JRS response
 */
function parseTrackingEvents(eventsData: any): Array<any> {
  if (!eventsData || !Array.isArray(eventsData)) {
    return [];
  }

  try {
    return eventsData.map((event: any) => ({
      status: event.status || event.Status || 'Unknown',
      location: event.location || event.Location || 'Unknown',
      timestamp: event.timestamp || event.Timestamp || event.date,
      description: event.description || event.Description || event.remarks
    }));
  } catch (error) {
    logger.error('Error parsing tracking events', { error, eventsData });
    return [];
  }
}
