import hashlib
import base64
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

# Constants to replace magic numbers
SHORT_URL_LENGTH = 6
DEFAULT_EXPIRY_DAYS = 60
HASH_TRUNCATE_LENGTH = 16
EXTENDED_HASH_LENGTH = 24
CUSTOM_SUFFIX_MAX_LENGTH = 20
CUSTOM_SUFFIX_MIN_LENGTH = 3

def generate_short_url(long_url: str, custom_suffix: Optional[str] = None) -> str:
    """
    Generate a short URL from a long URL.
    
    Args:
        long_url (str): The original long URL
        custom_suffix (str, optional): Custom suffix for the short URL
        
    Returns:
        str: A short URL identifier (6-8 characters)
        
    Raises:
        ValueError: If custom_suffix is invalid
    """
    if custom_suffix:
        # Validate custom suffix
        if not _is_valid_custom_suffix(custom_suffix):
            raise ValueError(
                f"Custom suffix must be {CUSTOM_SUFFIX_MIN_LENGTH}-{CUSTOM_SUFFIX_MAX_LENGTH} "
                f"alphanumeric characters, got: '{custom_suffix}'"
            )
        return custom_suffix
    
    # Create hash from URL and current timestamp for uniqueness
    timestamp = str(datetime.now(timezone.utc).timestamp())
    hash_input = f"{long_url}{timestamp}".encode('utf-8')
    
    # Generate SHA-256 hash
    hash_object = hashlib.sha256(hash_input)
    hash_hex = hash_object.hexdigest()
    
    # Convert to base64 and create short URL
    hash_b64 = base64.urlsafe_b64encode(bytes.fromhex(hash_hex[:HASH_TRUNCATE_LENGTH])).decode('utf-8')
    # Keep URL-safe characters but remove padding
    clean_b64 = hash_b64.replace('=', '')
    
    # If after cleaning we have less than required characters, use more of the hash
    if len(clean_b64) < SHORT_URL_LENGTH:
        # Use more of the original hash
        hash_b64 = base64.urlsafe_b64encode(bytes.fromhex(hash_hex[:EXTENDED_HASH_LENGTH])).decode('utf-8')
        clean_b64 = hash_b64.replace('=', '')
    
    return clean_b64[:SHORT_URL_LENGTH]


def _is_valid_custom_suffix(suffix: str) -> bool:
    """
    Validate custom suffix format and length.
    
    Args:
        suffix (str): Custom suffix to validate
        
    Returns:
        bool: True if valid, False otherwise
    """
    if not suffix:
        return False
    
    # Check length constraints
    if len(suffix) < CUSTOM_SUFFIX_MIN_LENGTH or len(suffix) > CUSTOM_SUFFIX_MAX_LENGTH:
        return False
    
    # Check for alphanumeric characters only (plus hyphens and underscores)
    pattern = re.compile(r'^[a-zA-Z0-9_-]+$')
    return bool(pattern.match(suffix))


def is_valid_url(url: str) -> bool:
    """
    Validate if a URL is properly formatted and secure.
    
    Args:
        url (str): URL to validate
        
    Returns:
        bool: True if URL is valid, False otherwise
    """
    if not url or not isinstance(url, str) or len(url) > 2048:
        return False
    
    # Block private IP ranges to prevent SSRF attacks
    private_ip_pattern = re.compile(
        r'^https?://(?:'
        r'10\.|'                                    # 10.0.0.0/8
        r'172\.(?:1[6-9]|2[0-9]|3[01])\.|'         # 172.16.0.0/12
        r'192\.168\.|'                              # 192.168.0.0/16
        r'127\.|'                                   # 127.0.0.0/8 (localhost)
        r'169\.254\.|'                              # 169.254.0.0/16 (link-local)
        r'0\.'                                      # 0.0.0.0/8
        r')', re.IGNORECASE
    )
    
    if private_ip_pattern.match(url):
        return False
    
    # Basic URL pattern with improved IP validation
    url_pattern = re.compile(
        r'^https?://'  # http:// or https://
        r'(?:'
        r'(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # domain
        r'localhost|'  # localhost (but blocked above)
        r'(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}'  # IP validation
        r'(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)'  # Last IP octet
        r')'
        r'(?::[0-9]+)?'  # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    
    return bool(url_pattern.match(url))


def calculate_expiry_date(days: int = DEFAULT_EXPIRY_DAYS) -> str:
    """
    Calculate expiry date from current time.
    
    Args:
        days (int): Number of days from now for expiry (default: 60)
        
    Returns:
        str: ISO format expiry date
        
    Raises:
        ValueError: If days is not positive
    """
    if days <= 0:
        raise ValueError(f"Days must be positive, got: {days}")
    
    expiry_date = datetime.now(timezone.utc) + timedelta(days=days)
    return expiry_date.isoformat()


def is_expired(expiry_date: str) -> bool:
    """
    Check if a URL has expired.
    
    Args:
        expiry_date (str): ISO format expiry date
        
    Returns:
        bool: True if expired, False otherwise
    """
    if not expiry_date:
        return True
    
    try:
        # Handle both timezone-aware and naive datetime strings
        if expiry_date.endswith('Z'):
            expiry_date = expiry_date[:-1] + '+00:00'
        elif '+' not in expiry_date and 'T' in expiry_date:
            # Assume UTC if no timezone info
            expiry_date = expiry_date + '+00:00'
            
        expiry = datetime.fromisoformat(expiry_date)
        current_time = datetime.now(timezone.utc)
        
        # Ensure both datetimes are timezone-aware for comparison
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        
        return current_time > expiry
    except (ValueError, TypeError) as e:
        # Log the error in production, but for now just return expired
        return True  # If we can't parse the date, consider it expired 