"""
Commons package for URL shortener utilities.
"""

from .url_utils import (
    generate_short_url,
    is_valid_url,
    calculate_expiry_date,
    is_expired,
    SHORT_URL_LENGTH,
    DEFAULT_EXPIRY_DAYS,
    CUSTOM_SUFFIX_MAX_LENGTH,
    CUSTOM_SUFFIX_MIN_LENGTH
)

from .lambda_utils import (
    get_base_url,
    extract_path_parameters,
    parse_request_body,
    create_json_response,
# create_html_response removed
    create_redirect_response,
    create_error_response,
    get_current_timestamp,
    ValidationError,
    ConflictError,
    LambdaError,
    NotFoundError
)

from .dynamodb_utils import (
    get_url_by_short_id,
    find_existing_url,
    create_url_mapping,
    update_click_count,
    delete_url_mapping,
    get_url_stats,
    DatabaseError
)

# HTML templates removed - using JSON responses only

__all__ = [
    # URL utilities
    'generate_short_url',
    'is_valid_url', 
    'calculate_expiry_date',
    'is_expired',
    'SHORT_URL_LENGTH',
    'DEFAULT_EXPIRY_DAYS',
    'CUSTOM_SUFFIX_MAX_LENGTH',
    'CUSTOM_SUFFIX_MIN_LENGTH',
    
    # Lambda utilities
    'get_base_url',
    'extract_path_parameters',
    'parse_request_body',
    'create_json_response',
# 'create_html_response' removed
    'create_redirect_response',
    'create_error_response',
    'get_current_timestamp',
    'ValidationError',
    'ConflictError',
    'LambdaError',
    'NotFoundError',
    
    # DynamoDB utilities
    'get_url_by_short_id',
    'find_existing_url',
    'create_url_mapping',
    'update_click_count',
    'delete_url_mapping',
    'get_url_stats',
    'DatabaseError',
    
# HTML templates removed - using JSON responses only
] 