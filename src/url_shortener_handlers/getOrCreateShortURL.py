import json
from datetime import datetime, timezone
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.logging import correlation_paths
from aws_lambda_powertools.metrics import MetricUnit

from commons.url_utils import generate_short_url, is_valid_url, calculate_expiry_date, is_expired
from commons.lambda_utils import (
    get_base_url, extract_path_parameters, parse_request_body,
    create_json_response, create_error_response, get_current_timestamp,
    ValidationError, ConflictError, LambdaError,
    HTTP_STATUS_OK, HTTP_STATUS_CREATED, HTTP_STATUS_BAD_REQUEST, 
    HTTP_STATUS_CONFLICT, HTTP_STATUS_INTERNAL_ERROR
)
from commons.dynamodb_utils import (
    find_existing_url, create_url_mapping, get_url_by_short_id,
    DatabaseError
)

# Initialize powertools
logger = Logger()
tracer = Tracer()
metrics = Metrics()

# Constants
DEFAULT_EXPIRY_DAYS = 60
MAX_COLLISION_RETRIES = 3


@tracer.capture_lambda_handler
@logger.inject_lambda_context(correlation_id_path=correlation_paths.API_GATEWAY_REST)
@metrics.log_metrics(capture_cold_start_metric=True)
def lambda_handler(event, context):
    """
    Lambda handler for getting or creating short URLs.
    
    Expected input:
    {
        "longUrl": "https://example.com/very/long/url",
        "customSuffix": "optional-custom-suffix"  // optional
    }
    
    Returns:
    {
        "shortUrl": "https://short.hireko.com/abc123",
        "longUrl": "https://example.com/very/long/url",
        "expiryDate": "2024-03-15T10:30:00",
        "created": true  // false if URL already existed
    }
    """
    
    try:
        # Extract path information for multi-tenant support
        short_id, stage, tenant = extract_path_parameters(event)
        if stage and tenant:
            logger.info(f"Request from stage: {stage}, tenant: {tenant}")
        
        # Parse and validate request body
        body = parse_request_body(event)
        long_url = body.get('longUrl')
        custom_suffix = body.get('customSuffix')
        
        # Validate required fields
        if not long_url:
            raise ValidationError('Missing required field: longUrl')
        
        if not is_valid_url(long_url):
            raise ValidationError('Invalid URL format')
        
        # Check if URL already exists (using GSI query instead of scan)
        existing_item = find_existing_url(long_url)
        if existing_item:
            logger.info(f"Found existing non-expired short URL for: {long_url}")
            metrics.add_metric(name="ExistingUrlReturned", unit=MetricUnit.Count, value=1)
            
            base_url = get_base_url(event)
            return create_json_response(
                status_code=HTTP_STATUS_OK,
                body={
                    'shortUrl': f"{base_url}/{existing_item['shortId']}",
                    'longUrl': existing_item['longUrl'],
                    'expiryDate': existing_item['expiryDate'],
                    'created': False
                }
            )
        
        # Generate short URL with collision handling
        short_id, created_item = create_short_url_with_retry(
            long_url=long_url,
            custom_suffix=custom_suffix
        )
        
        logger.info(f"Created new short URL: {short_id} -> {long_url}")
        metrics.add_metric(name="NewUrlCreated", unit=MetricUnit.Count, value=1)
        
        base_url = get_base_url(event)
        return create_json_response(
            status_code=HTTP_STATUS_CREATED,
            body={
                'shortUrl': f"{base_url}/{short_id}",
                'longUrl': long_url,
                'expiryDate': created_item['expiryDate'],
                'created': True
            }
        )
        
    except ValidationError as e:
        return create_error_response(
            status_code=e.status_code,
            error_message=e.message,
            logger=logger,
            metrics=metrics,
            metric_name="ValidationErrors"
        )
        
    except ConflictError as e:
        return create_error_response(
            status_code=e.status_code,
            error_message=e.message,
            logger=logger,
            metrics=metrics,
            metric_name="CustomSuffixConflict"
        )
        
    except DatabaseError as e:
        return create_error_response(
            status_code=e.status_code,
            error_message="Database operation failed",
            logger=logger,
            metrics=metrics,
            metric_name="DatabaseErrors"
        )
        
    except json.JSONDecodeError as e:
        return create_error_response(
            status_code=HTTP_STATUS_BAD_REQUEST,
            error_message="Invalid JSON format",
            logger=logger,
            metrics=metrics,
            metric_name="JsonParseErrors"
        )
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return create_error_response(
            status_code=HTTP_STATUS_INTERNAL_ERROR,
            error_message="Internal server error",
            logger=logger,
            metrics=metrics,
            metric_name="UnexpectedErrors"
        )


def create_short_url_with_retry(long_url: str, custom_suffix: str = None) -> tuple:
    """
    Create short URL with collision retry logic.
    
    Args:
        long_url: The original long URL
        custom_suffix: Optional custom suffix
        
    Returns:
        Tuple of (short_id, created_item)
        
    Raises:
        ConflictError: If custom suffix already exists
        DatabaseError: If database operations fail
        ValidationError: If custom suffix is invalid
    """
    # Calculate expiry date and TTL timestamp
    expiry_date = calculate_expiry_date(DEFAULT_EXPIRY_DAYS)
    expiry_datetime = datetime.fromisoformat(expiry_date.replace('Z', '+00:00') if expiry_date.endswith('Z') else expiry_date)
    if expiry_datetime.tzinfo is None:
        expiry_datetime = expiry_datetime.replace(tzinfo=timezone.utc)
    ttl_timestamp = int(expiry_datetime.timestamp())
    
    for attempt in range(MAX_COLLISION_RETRIES):
        # Generate short ID
        if custom_suffix and attempt == 0:
            # Only try custom suffix on first attempt
            short_id = generate_short_url(long_url, custom_suffix)
        else:
            # Generate random short ID, adding entropy for retries
            entropy_suffix = f"_{attempt}_{get_current_timestamp()}" if attempt > 0 else ""
            short_id = generate_short_url(f"{long_url}{entropy_suffix}")
        
        try:
            # Create URL mapping atomically - DynamoDB handles the race condition
            created_item = create_url_mapping(
                short_id=short_id,
                long_url=long_url,
                expiry_date=expiry_date,
                ttl_timestamp=ttl_timestamp
            )
            
            return short_id, created_item
            
        except ConflictError:
            if custom_suffix:
                # Don't retry for custom suffix conflicts
                raise
            
            if attempt == MAX_COLLISION_RETRIES - 1:
                # Last attempt failed
                logger.error(f"Failed to create short URL after {MAX_COLLISION_RETRIES} attempts")
                raise DatabaseError("Unable to generate unique short URL after multiple attempts")
            
            # Log collision and retry
            logger.warning(f"Short ID collision detected on attempt {attempt + 1}: {short_id}")
            metrics.add_metric(name="ShortIdCollision", unit=MetricUnit.Count, value=1)
    
    # This should never be reached due to the exception handling above
    raise DatabaseError("Unexpected error in short URL creation") 