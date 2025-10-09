import unittest
import sys
import os

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from commons.url_utils import (
    generate_short_url, is_valid_url, calculate_expiry_date, is_expired,
    SHORT_URL_LENGTH, DEFAULT_EXPIRY_DAYS, CUSTOM_SUFFIX_MAX_LENGTH, CUSTOM_SUFFIX_MIN_LENGTH
)
from datetime import datetime, timedelta, timezone


class TestUrlUtils(unittest.TestCase):
    
    def test_generate_short_url_constants(self):
        """Test that constants are properly defined"""
        self.assertEqual(SHORT_URL_LENGTH, 6)
        self.assertEqual(DEFAULT_EXPIRY_DAYS, 60)
        self.assertEqual(CUSTOM_SUFFIX_MIN_LENGTH, 3)
        self.assertEqual(CUSTOM_SUFFIX_MAX_LENGTH, 20)
    
    def test_generate_short_url_length(self):
        """Test short URL generation produces correct length"""
        long_url = "https://example.com/very/long/url/path"
        short_id = generate_short_url(long_url)
        
        # Should generate a string of SHORT_URL_LENGTH
        self.assertEqual(len(short_id), SHORT_URL_LENGTH)
        self.assertIsInstance(short_id, str)
        
        # Should only contain URL-safe characters (no removed characters)
        import re
        pattern = re.compile(r'^[a-zA-Z0-9_-]+$')
        self.assertTrue(pattern.match(short_id), f"Short ID contains invalid characters: {short_id}")
    
    def test_generate_short_url_uniqueness(self):
        """Test short URL generation uniqueness (with high probability)"""
        long_url = "https://example.com/very/long/url/path"
        short_ids = set()
        
        # Generate multiple short IDs and check for uniqueness
        for _ in range(100):  # Generate 100 to test uniqueness
            short_id = generate_short_url(long_url)
            short_ids.add(short_id)
        
        # Should have high uniqueness (allow for very small chance of collision)
        self.assertGreater(len(short_ids), 95, "Short URL generation should be highly unique")
    
    def test_generate_short_url_with_valid_custom_suffix(self):
        """Test short URL generation with valid custom suffix"""
        long_url = "https://example.com"
        custom_suffix = "custom123"
        
        short_id = generate_short_url(long_url, custom_suffix)
        self.assertEqual(short_id, custom_suffix)
    
    def test_generate_short_url_with_invalid_custom_suffix(self):
        """Test short URL generation with invalid custom suffix raises error"""
        long_url = "https://example.com"
        
        # Test too short
        with self.assertRaises(ValueError):
            generate_short_url(long_url, "ab")
        
        # Test too long
        with self.assertRaises(ValueError):
            generate_short_url(long_url, "a" * (CUSTOM_SUFFIX_MAX_LENGTH + 1))
        
        # Test invalid characters
        with self.assertRaises(ValueError):
            generate_short_url(long_url, "custom@123")
        
        # Test empty string
        with self.assertRaises(ValueError):
            generate_short_url(long_url, " ")
        
        # Test None (should not raise error as it's handled differently)
        short_id = generate_short_url(long_url, None)
        self.assertEqual(len(short_id), SHORT_URL_LENGTH)
    
    def test_is_valid_url_valid_cases(self):
        """Test URL validation with valid URLs"""
        valid_urls = [
            "https://example.com",
            "http://example.com",
            "https://sub.example.com",
            "https://example.com/path",
            "https://example.com:8080",
            "http://localhost:3000",
            "https://example.com/path/to/resource?query=value#fragment",
        ]
        
        for url in valid_urls:
            with self.subTest(url=url):
                self.assertTrue(is_valid_url(url), f"URL should be valid: {url}")
    
    def test_is_valid_url_invalid_cases(self):
        """Test URL validation with invalid URLs"""
        invalid_urls = [
            "not-a-url",
            "ftp://example.com",  # Only http/https allowed
            "example.com",  # Missing protocol
            "",
            "https://",
            "http://",
            "https://999.999.999.999",  # Invalid IP
            "https://256.1.1.1",  # Invalid IP octet
            None,
            123,  # Non-string type
        ]
        
        for url in invalid_urls:
            with self.subTest(url=url):
                self.assertFalse(is_valid_url(url), f"URL should be invalid: {url}")
    
    def test_calculate_expiry_date_default(self):
        """Test expiry date calculation with default days"""
        expiry_date = calculate_expiry_date()
        expiry_datetime = datetime.fromisoformat(expiry_date.replace('Z', '+00:00') if expiry_date.endswith('Z') else expiry_date)
        
        # Should be approximately DEFAULT_EXPIRY_DAYS from now
        expected_date = datetime.now(timezone.utc) + timedelta(days=DEFAULT_EXPIRY_DAYS)
        time_diff = abs((expiry_datetime - expected_date).total_seconds())
        
        # Allow 5 seconds difference for test execution time
        self.assertLess(time_diff, 5, "Expiry date should be close to expected default")
    
    def test_calculate_expiry_date_custom_days(self):
        """Test expiry date calculation with custom days"""
        custom_days = 30
        expiry_date = calculate_expiry_date(custom_days)
        expiry_datetime = datetime.fromisoformat(expiry_date.replace('Z', '+00:00') if expiry_date.endswith('Z') else expiry_date)
        
        expected_date = datetime.now(timezone.utc) + timedelta(days=custom_days)
        time_diff = abs((expiry_datetime - expected_date).total_seconds())
        
        self.assertLess(time_diff, 5, "Expiry date should be close to expected custom days")
    
    def test_calculate_expiry_date_invalid_days(self):
        """Test expiry date calculation with invalid days"""
        with self.assertRaises(ValueError):
            calculate_expiry_date(0)
        
        with self.assertRaises(ValueError):
            calculate_expiry_date(-1)
    
    def test_is_expired_future_date(self):
        """Test expiry checking with future date (not expired)"""
        future_date = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        self.assertFalse(is_expired(future_date))
        
        # Test with Z suffix
        future_date_z = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat() + 'Z'
        self.assertTrue(is_expired(future_date_z))
    
    def test_is_expired_past_date(self):
        """Test expiry checking with past date (expired)"""
        past_date = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        self.assertTrue(is_expired(past_date))
        
        # Test with Z suffix
        past_date_z = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat() + 'Z'
        self.assertTrue(is_expired(past_date_z))
    
    def test_is_expired_invalid_formats(self):
        """Test expiry checking with invalid date formats (should be treated as expired)"""
        invalid_dates = [
            "invalid-date",
            "",
            None,
            "2024-13-45T25:70:80",  # Invalid date components
            "not-a-date-at-all",
        ]
        
        for invalid_date in invalid_dates:
            with self.subTest(date=invalid_date):
                self.assertTrue(is_expired(invalid_date), f"Invalid date should be treated as expired: {invalid_date}")
    
    def test_is_expired_timezone_handling(self):
        """Test expiry checking handles different timezone formats"""
        # Test naive datetime (should be treated as UTC)
        naive_future = datetime.now(timezone.utc) + timedelta(days=1)
        naive_date_str = naive_future.replace(tzinfo=None).isoformat()
        self.assertFalse(is_expired(naive_date_str))
        
        # Test explicit UTC timezone
        utc_future = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        self.assertFalse(is_expired(utc_future))


if __name__ == '__main__':
    unittest.main() 