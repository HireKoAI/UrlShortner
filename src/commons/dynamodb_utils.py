"""
DynamoDB utilities for URL shortener operations.
"""

import os
import boto3
from typing import Optional, Dict, Any, List
from datetime import datetime, timezone
from botocore.exceptions import ClientError
from aws_lambda_powertools import Logger

from .lambda_utils import LambdaError, NotFoundError, ConflictError, get_current_timestamp
from .url_utils import is_expired

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(table_name) if table_name else None

# Constants
GSI_LONG_URL_INDEX = 'longUrl-index'
MAX_RETRY_ATTEMPTS = 3

logger = Logger()


class DatabaseError(LambdaError):
    """Exception for database operation errors."""
    
    def __init__(self, message: str, original_error: Exception = None):
        super().__init__(f"Database error: {message}", 500)
        self.original_error = original_error


def _handle_client_error(error: ClientError, operation: str) -> None:
    """
    Handle and convert DynamoDB ClientError to appropriate exceptions.
    
    Args:
        error: The ClientError from DynamoDB
        operation: Description of the operation that failed
        
    Raises:
        ConflictError: For conditional check failures
        NotFoundError: For resource not found
        DatabaseError: For other database errors
    """
    error_code = error.response.get('Error', {}).get('Code', 'Unknown')
    error_message = error.response.get('Error', {}).get('Message', str(error))
    
    logger.error(f"DynamoDB {operation} failed: {error_code} - {error_message}")
    
    if error_code == 'ConditionalCheckFailedException':
        raise ConflictError("Resource already exists or condition not met")
    elif error_code == 'ResourceNotFoundException':
        raise NotFoundError("Resource not found")
    else:
        raise DatabaseError(f"{operation} failed: {error_message}", error)


def get_url_by_short_id(short_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve URL mapping by short ID.
    
    Args:
        short_id: The short URL identifier
        
    Returns:
        Dict containing URL mapping or None if not found
        
    Raises:
        DatabaseError: If database operation fails
    """
    if not table:
        raise DatabaseError("DynamoDB table not configured")
    
    try:
        response = table.get_item(Key={'shortId': short_id})
        return response.get('Item')
    except ClientError as e:
        _handle_client_error(e, "get_item")


def find_existing_url(long_url: str) -> Optional[Dict[str, Any]]:
    """
    Find existing non-expired URL mapping by long URL using GSI.
    
    Args:
        long_url: The original long URL
        
    Returns:
        Dict containing URL mapping or None if not found
        
    Raises:
        DatabaseError: If database operation fails
    """
    if not table:
        raise DatabaseError("DynamoDB table not configured")
    
    try:
        # Use GSI query instead of expensive scan
        response = table.query(
            IndexName=GSI_LONG_URL_INDEX,
            KeyConditionExpression=boto3.dynamodb.conditions.Key('longUrl').eq(long_url),
            # Only return items that haven't expired
            FilterExpression=boto3.dynamodb.conditions.Attr('ttlTimestamp').gt(
                int(datetime.now(timezone.utc).timestamp())
            )
        )
        
        items = response.get('Items', [])
        
        # Return the first non-expired item
        for item in items:
            if not is_expired(item.get('expiryDate', '')):
                return item
        
        return None
        
    except ClientError as e:
        _handle_client_error(e, "query_existing_url")


def create_url_mapping(
    short_id: str,
    long_url: str,
    expiry_date: str,
    ttl_timestamp: int,
    click_count: int = 0
) -> Dict[str, Any]:
    """
    Create a new URL mapping in DynamoDB.
    
    Args:
        short_id: The short URL identifier
        long_url: The original long URL
        expiry_date: ISO format expiry date
        ttl_timestamp: Unix timestamp for TTL
        click_count: Initial click count (default: 0)
        
    Returns:
        Dict containing the created item
        
    Raises:
        ConflictError: If short_id already exists
        DatabaseError: If database operation fails
    """
    if not table:
        raise DatabaseError("DynamoDB table not configured")
    
    item = {
        'shortId': short_id,
        'longUrl': long_url,
        'createdAt': get_current_timestamp(),
        'expiryDate': expiry_date,
        'ttlTimestamp': ttl_timestamp,
        'clickCount': click_count
    }
    
    try:
        table.put_item(
            Item=item,
            ConditionExpression='attribute_not_exists(shortId)'
        )
        return item
        
    except ClientError as e:
        _handle_client_error(e, "create_url_mapping")


def update_click_count(short_id: str) -> bool:
    """
    Increment click count and update last accessed timestamp.
    
    Args:
        short_id: The short URL identifier
        
    Returns:
        bool: True if update was successful, False otherwise
    """
    if not table:
        logger.warning("DynamoDB table not configured, skipping click count update")
        return False
    
    try:
        table.update_item(
            Key={'shortId': short_id},
            UpdateExpression='SET clickCount = if_not_exists(clickCount, :zero) + :inc, lastAccessedAt = :timestamp',
            ExpressionAttributeValues={
                ':inc': 1,
                ':zero': 0,
                ':timestamp': get_current_timestamp()
            }
        )
        return True
        
    except ClientError as e:
        # Don't raise exception for click count updates - it's not critical
        logger.warning(f"Failed to update click count for {short_id}: {e}")
        return False


def delete_url_mapping(short_id: str) -> bool:
    """
    Delete URL mapping by short ID.
    
    Args:
        short_id: The short URL identifier
        
    Returns:
        bool: True if deletion was successful, False if item didn't exist
        
    Raises:
        DatabaseError: If database operation fails
    """
    if not table:
        raise DatabaseError("DynamoDB table not configured")
    
    try:
        response = table.delete_item(
            Key={'shortId': short_id},
            ReturnValues='ALL_OLD'
        )
        return 'Attributes' in response
        
    except ClientError as e:
        _handle_client_error(e, "delete_url_mapping")


def get_url_stats(short_id: str) -> Optional[Dict[str, Any]]:
    """
    Get URL statistics including click count and access history.
    
    Args:
        short_id: The short URL identifier
        
    Returns:
        Dict containing URL statistics or None if not found
        
    Raises:
        DatabaseError: If database operation fails
    """
    item = get_url_by_short_id(short_id)
    if not item:
        return None
    
    return {
        'shortId': item.get('shortId'),
        'longUrl': item.get('longUrl'),
        'createdAt': item.get('createdAt'),
        'expiryDate': item.get('expiryDate'),
        'clickCount': item.get('clickCount', 0),
        'lastAccessedAt': item.get('lastAccessedAt'),
        'isExpired': is_expired(item.get('expiryDate', ''))
    }


def batch_get_urls(short_ids: List[str]) -> List[Dict[str, Any]]:
    """
    Retrieve multiple URL mappings by short IDs.
    
    Args:
        short_ids: List of short URL identifiers
        
    Returns:
        List of URL mapping dictionaries
        
    Raises:
        DatabaseError: If database operation fails
    """
    if not table or not short_ids:
        return []
    
    try:
        # DynamoDB batch_get_item has a limit of 100 items
        batch_size = 100
        results = []
        
        for i in range(0, len(short_ids), batch_size):
            batch = short_ids[i:i + batch_size]
            
            response = dynamodb.batch_get_item(
                RequestItems={
                    table_name: {
                        'Keys': [{'shortId': short_id} for short_id in batch]
                    }
                }
            )
            
            results.extend(response.get('Responses', {}).get(table_name, []))
        
        return results
        
    except ClientError as e:
        _handle_client_error(e, "batch_get_urls")


 