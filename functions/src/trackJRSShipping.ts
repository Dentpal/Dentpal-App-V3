
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
      const rawStatus = details.status || details.Status || 'Unknown';
      const consolidatedStatus = consolidateJRSStatus(rawStatus);
      
      return {
        trackingId: trackingId,
        status: rawStatus,
        consolidatedStatus: consolidatedStatus,
        statusDescription: getStatusCategoryDescription(consolidatedStatus),
        location: details.location || details.Location,
        timestamp: details.timestamp || details.Timestamp || details.lastUpdate,
        events: parseTrackingEvents(details.events || details.Events || details.history)
      };
    }
    
    // If response has a different structure, try to extract basic info
    if (responseData.status || responseData.Status) {
      const rawStatus = responseData.status || responseData.Status;
      const consolidatedStatus = consolidateJRSStatus(rawStatus);
      
      return {
        trackingId: trackingId,
        status: rawStatus,
        consolidatedStatus: consolidatedStatus,
        statusDescription: getStatusCategoryDescription(consolidatedStatus),
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
      consolidatedStatus: 'shipping',
      statusDescription: 'Package is on its way to you',
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
      description: event.description || event.Description || event.remarks,
      // Add consolidated status for the app
      consolidatedStatus: consolidateJRSStatus(event.status || event.Status || 'Unknown')
    }));
  } catch (error) {
    logger.error('Error parsing tracking events', { error, eventsData });
    return [];
  }
}

/**
 * Our simplified order status system:
 * - "pending" (unpaid)
 * - "confirmed" (paid)
 * - "to_ship" (processing)
 * - "shipping" (in transit/shipping)
 * - "delivered" (delivered)
 * - "failed_delivery" (delivery failed)
 * - "cancelled" (cancelled)
 * - "return_requested" (return/refund requested)
 * - "returned" (returned)
 * - "refunded" (refunded)
 */
type ConsolidatedStatus = 
  | 'pending'
  | 'confirmed'
  | 'to_ship'
  | 'shipping'
  | 'delivered'
  | 'failed_delivery'
  | 'cancelled'
  | 'returned'
  | 'refunded'
  | 'unknown';

/**
 * Consolidate JRS tracking statuses into our simplified status system
 * Based on JRS statuses from jrs-statuses.txt
 */
function consolidateJRSStatus(jrsStatus: string): ConsolidatedStatus {
  if (!jrsStatus) return 'unknown';
  
  const status = jrsStatus.toLowerCase().trim();

  // DELIVERED - Successfully delivered
  if (
    status.includes('delivered') ||
    status.includes('claimed') ||
    status === 'delivered to'
  ) {
    return 'delivered';
  }

  // FAILED DELIVERY - Delivery attempted but failed
  if (
    status.includes('incomplete address') ||
    status.includes('always closed') ||
    status.includes('no authorized person') ||
    status.includes('refused to accept') ||
    status.includes('no such address') ||
    status.includes('addressee unknown') ||
    status.includes('addressee moved out') ||
    status.includes('house burned') ||
    status.includes('demolished') ||
    status.includes('no such number') ||
    status.includes('no such street') ||
    status.includes('no such barangay') ||
    status.includes('company moved out') ||
    status.includes('company unknown') ||
    status.includes('building burned') ||
    status.includes('deceased') ||
    status.includes('addressee no longer connected') ||
    status.includes('problematic') ||
    status.includes('unclaimed') ||
    status.includes('out of delivery zone')
  ) {
    return 'failed_delivery';
  }

  // RETURNED - Package returned to sender
  if (
    status.includes('returned to sender') ||
    status.includes('returned to originating') ||
    status.includes('back load')
  ) {
    return 'returned';
  }

  // CANCELLED - Order/Shipment cancelled
  if (
    status.includes('cancelled') ||
    status.includes('missing')
  ) {
    return 'cancelled';
  }

  // SHIPPING - Package is in transit
  if (
    status.includes('intransit') ||
    status.includes('in transit') ||
    status.includes('transhipping') ||
    status.includes('departed') ||
    status.includes('arrived at') ||
    status.includes('for delivery') ||
    status.includes('ready for delivery') ||
    status.includes('scheduled for delivery') ||
    status.includes('forwarded to') ||
    status.includes('vessel eta') ||
    status.includes('container under custom') ||
    status.includes('arrive at airport') ||
    status.includes('customs release') ||
    status.includes('shortshipped') ||
    status.includes('distribution hub')
  ) {
    return 'shipping';
  }

  // TO SHIP (PROCESSING) - Package accepted, being prepared
  if (
    status.includes('accepted at origin') ||
    status.includes('at originating branch') ||
    status.includes('ready for pick-up') ||
    status.includes('other instruction') ||
    status.includes('arrive at head office')
  ) {
    return 'to_ship';
  }

  // Default to unknown for unrecognized statuses
  logger.warn('Unrecognized JRS status, defaulting to unknown', { jrsStatus });
  return 'unknown';
}

/**
 * Get the JRS status category description
 */
function getStatusCategoryDescription(consolidatedStatus: ConsolidatedStatus): string {
  switch (consolidatedStatus) {
    case 'pending':
      return 'Awaiting payment confirmation';
    case 'confirmed':
      return 'Payment confirmed, preparing order';
    case 'to_ship':
      return 'Order accepted, being prepared for shipment';
    case 'shipping':
      return 'Package is on its way to you';
    case 'delivered':
      return 'Package has been delivered successfully';
    case 'failed_delivery':
      return 'Delivery attempt was unsuccessful';
    case 'cancelled':
      return 'Shipment has been cancelled';
    case 'returned':
      return 'Package is being returned to sender';
    case 'refunded':
      return 'Order has been refunded';
    default:
      return 'Status information unavailable';
  }
}

// Export helper functions for use in other modules
export { consolidateJRSStatus, getStatusCategoryDescription, ConsolidatedStatus };

