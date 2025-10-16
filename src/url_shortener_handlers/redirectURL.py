import json
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.logging import correlation_paths
from aws_lambda_powertools.metrics import MetricUnit

from commons.url_utils import is_expired
from commons.lambda_utils import (
    extract_path_parameters, create_json_response, create_redirect_response,
    create_error_response, ValidationError, LambdaError,
    HTTP_STATUS_BAD_REQUEST, HTTP_STATUS_NOT_FOUND, HTTP_STATUS_GONE, 
    HTTP_STATUS_INTERNAL_ERROR
)
from commons.dynamodb_utils import get_url_by_short_id, update_click_count, DatabaseError

# Initialize powertools
logger = Logger()
tracer = Tracer()
metrics = Metrics(namespace="UrlShortenerService")


@tracer.capture_lambda_handler
@logger.inject_lambda_context(correlation_id_path=correlation_paths.API_GATEWAY_REST)
@metrics.log_metrics(capture_cold_start_metric=True)
def lambda_handler(event, context):
    """
    Lambda handler for URL redirection.
    
    Expected input from API Gateway:
    - Path parameter: shortId
    
    Returns:
    - 302 redirect to the original URL
    - 404 JSON if short URL not found or expired
    """
    
    try:
        # Extract short ID from path parameters
        short_id, stage, tenant = extract_path_parameters(event)
        
        if not short_id:
            raise ValidationError("Missing short URL identifier")
        
        # Look up the short URL in DynamoDB
        item = get_url_by_short_id(short_id)
        
        if not item:
            logger.info(f"Short URL not found: {short_id}")
            metrics.add_metric(name="UrlNotFound", unit=MetricUnit.Count, value=1)
            
            return create_json_response(
                status_code=HTTP_STATUS_NOT_FOUND,
                body={
                    "error": "URL not found",
                    "message": "The short URL you're looking for doesn't exist.",
                    "shortId": short_id
                }
            )
        
        long_url = item.get('longUrl')
        expiry_date = item.get('expiryDate')
        
        # Check if URL has expired
        if is_expired(expiry_date):
            logger.info(f"Short URL expired: {short_id}")
            metrics.add_metric(name="UrlExpired", unit=MetricUnit.Count, value=1)
            
            return create_json_response(
                status_code=HTTP_STATUS_GONE,
                body={
                    "error": "URL expired",
                    "message": "This short URL has expired and is no longer valid.",
                    "shortId": short_id,
                    "expiredAt": expiry_date
                }
            )
        
        # Update click count (fire-and-forget)
        click_updated = update_click_count(short_id)
        if not click_updated:
            logger.warning(f"Failed to update click count for {short_id}")
        
        # Log successful redirect
        logger.info(f"Redirecting {short_id} to {long_url[:50]}...")  # Truncate for security
        metrics.add_metric(name="SuccessfulRedirects", unit=MetricUnit.Count, value=1)
        
        # Return 302 redirect
        return create_redirect_response(long_url)
        
    except ValidationError as e:
        return create_error_response(
            status_code=e.status_code,
            error_message=e.message,
            logger=logger,
            metrics=metrics,
            metric_name="MissingShortId"
        )
        
    except DatabaseError as e:
        logger.error(f"Database error for {short_id}: {str(e)}")
        metrics.add_metric(name="DatabaseErrors", unit=MetricUnit.Count, value=1)
        
        return create_json_response(
            status_code=HTTP_STATUS_INTERNAL_ERROR,
            body={
                "error": "Service temporarily unavailable",
                "message": "Please try again later."
            }
        )
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        metrics.add_metric(name="UnexpectedErrors", unit=MetricUnit.Count, value=1)
        
        return create_json_response(
            status_code=HTTP_STATUS_INTERNAL_ERROR,
            body={
                "error": "Internal server error",
                "message": "An unexpected error occurred."
            }
        ) 