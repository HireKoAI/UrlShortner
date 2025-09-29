"""
Common utilities for Lambda functions to eliminate code duplication.
"""

import json
import os
from typing import Dict, Any, Optional, Tuple
from datetime import datetime, timezone
from aws_lambda_powertools import Logger, Metrics
from aws_lambda_powertools.metrics import MetricUnit

# Constants
HTTP_STATUS_OK = 200
HTTP_STATUS_CREATED = 201
HTTP_STATUS_BAD_REQUEST = 400
HTTP_STATUS_NOT_FOUND = 404
HTTP_STATUS_CONFLICT = 409
HTTP_STATUS_GONE = 410
HTTP_STATUS_INTERNAL_ERROR = 500

# CORS headers
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
}

# Common response headers
JSON_HEADERS = {
    'Content-Type': 'application/json',
    **CORS_HEADERS
}

# HTML headers removed - using JSON responses only

REDIRECT_HEADERS = {
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Pragma': 'no-cache',
    'Expires': '0'
}


def get_base_url(event: Dict[str, Any]) -> str:
    """
    Get base URL from environment variable or construct from API Gateway context.
    
    Args:
        event: Lambda event object
        
    Returns:
        str: Base URL for the service
    """
    base_url = os.environ.get('BASE_URL')
    if base_url:
        return base_url
    
    # Construct from API Gateway context
    headers = event.get('headers', {})
    host = headers.get('Host', 'unknown-host')
    stage = event.get('requestContext', {}).get('stage', 'unknown-stage')
    return f"https://{host}/{stage}"


def extract_path_parameters(event: Dict[str, Any]) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Extract path parameters from API Gateway event, handling both direct and proxy paths.
    
    Args:
        event: Lambda event object
        
    Returns:
        Tuple of (short_id, stage, tenant) - any can be None if not found
    """
    path_params = event.get('pathParameters', {})
    short_id = path_params.get('shortId')
    stage = None
    tenant = None
    
    # If using proxy integration, extract from proxy path
    if 'proxy' in path_params:
        proxy_path = path_params.get('proxy', '')
        # Expected format: UrlShortner/stage/{stage}/tenant/{tenant}/shorten or /{shortId}
        path_parts = [part for part in proxy_path.split('/') if part]
        
        if len(path_parts) >= 4:
            # Multi-tenant format: stage/{stage}/tenant/{tenant}/...
            if len(path_parts) >= 4 and path_parts[0] == 'stage' and path_parts[2] == 'tenant':
                stage = path_parts[1]
                tenant = path_parts[3]
                if len(path_parts) > 4:
                    # Could be shortId or 'shorten' endpoint
                    short_id = path_parts[-1] if path_parts[-1] != 'shorten' else None
        elif len(path_parts) == 1:
            # Simple format: just the shortId
            short_id = path_parts[0]
    
    return short_id, stage, tenant


def parse_request_body(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse and validate request body from Lambda event.
    
    Args:
        event: Lambda event object
        
    Returns:
        Dict containing parsed body
        
    Raises:
        json.JSONDecodeError: If body is not valid JSON
        ValueError: If body is missing or invalid
    """
    body = event.get('body')
    
    if not body:
        raise ValueError("Request body is required")
    
    if isinstance(body, str):
        try:
            return json.loads(body)
        except json.JSONDecodeError as e:
            raise json.JSONDecodeError(f"Invalid JSON in request body: {str(e)}", body, 0)
    elif isinstance(body, dict):
        return body
    else:
        raise ValueError(f"Invalid body type: {type(body)}")


def create_json_response(
    status_code: int,
    body: Dict[str, Any],
    additional_headers: Optional[Dict[str, str]] = None
) -> Dict[str, Any]:
    """
    Create a standardized JSON response for Lambda.
    
    Args:
        status_code: HTTP status code
        body: Response body dictionary
        additional_headers: Optional additional headers
        
    Returns:
        Dict: Lambda response object
    """
    headers = JSON_HEADERS.copy()
    if additional_headers:
        headers.update(additional_headers)
    
    return {
        'statusCode': status_code,
        'headers': headers,
        'body': json.dumps(body, default=str)  # default=str handles datetime objects
    }


# create_html_response removed - using JSON responses only


def create_redirect_response(location: str) -> Dict[str, Any]:
    """
    Create a 302 redirect response.
    
    Args:
        location: URL to redirect to
        
    Returns:
        Dict: Lambda response object
    """
    headers = REDIRECT_HEADERS.copy()
    headers['Location'] = location
    
    return {
        'statusCode': 302,
        'headers': headers,
        'body': ''
    }


def create_error_response(
    status_code: int,
    error_message: str,
    logger: Logger,
    metrics: Metrics,
    metric_name: str = "Errors"
) -> Dict[str, Any]:
    """
    Create a standardized error response with logging and metrics.
    
    Args:
        status_code: HTTP status code
        error_message: Error message to return
        logger: Lambda Powertools logger
        metrics: Lambda Powertools metrics
        metric_name: Metric name for error tracking
        
    Returns:
        Dict: Lambda response object
    """
    logger.error(f"Error {status_code}: {error_message}")
    metrics.add_metric(name=metric_name, unit=MetricUnit.Count, value=1)
    
    return create_json_response(
        status_code=status_code,
        body={'error': error_message}
    )


def get_current_timestamp() -> str:
    """
    Get current UTC timestamp in ISO format.
    
    Returns:
        str: ISO formatted timestamp
    """
    return datetime.now(timezone.utc).isoformat()


class LambdaError(Exception):
    """Base exception class for Lambda function errors."""
    
    def __init__(self, message: str, status_code: int = HTTP_STATUS_INTERNAL_ERROR):
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class ValidationError(LambdaError):
    """Exception for validation errors."""
    
    def __init__(self, message: str):
        super().__init__(message, HTTP_STATUS_BAD_REQUEST)


class NotFoundError(LambdaError):
    """Exception for resource not found errors."""
    
    def __init__(self, message: str = "Resource not found"):
        super().__init__(message, HTTP_STATUS_NOT_FOUND)


class ConflictError(LambdaError):
    """Exception for resource conflict errors."""
    
    def __init__(self, message: str = "Resource conflict"):
        super().__init__(message, HTTP_STATUS_CONFLICT) 