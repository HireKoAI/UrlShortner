import unittest
import json
import sys
import os

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from commons.lambda_utils import (
    get_base_url, extract_path_parameters, parse_request_body,
    create_json_response, create_redirect_response,
    create_error_response, get_current_timestamp,
    ValidationError, ConflictError, LambdaError, NotFoundError,
    HTTP_STATUS_OK, HTTP_STATUS_CREATED, HTTP_STATUS_BAD_REQUEST,
    HTTP_STATUS_NOT_FOUND, HTTP_STATUS_CONFLICT, HTTP_STATUS_INTERNAL_ERROR
)
from aws_lambda_powertools import Logger, Metrics
from datetime import datetime, timezone


class TestLambdaUtils(unittest.TestCase):
    
    def setUp(self):
        """Set up test fixtures"""
        self.logger = Logger()
        self.metrics = Metrics()
    
    def test_get_base_url_from_environment(self):
        """Test getting base URL from environment variable"""
        # Mock environment variable
        import os
        os.environ['BASE_URL'] = 'https://short.example.com'
        
        event = {'headers': {'Host': 'api.amazonaws.com'}}
        base_url = get_base_url(event)
        
        self.assertEqual(base_url, 'https://short.example.com')
        
        # Clean up
        del os.environ['BASE_URL']
    
    def test_get_base_url_from_event(self):
        """Test constructing base URL from API Gateway event"""
        event = {
            'headers': {'Host': 'api.example.com'},
            'requestContext': {'stage': 'prod'}
        }
        
        base_url = get_base_url(event)
        self.assertEqual(base_url, 'https://api.example.com/prod')
    
    def test_get_base_url_fallback(self):
        """Test base URL construction with missing data"""
        event = {}
        base_url = get_base_url(event)
        self.assertEqual(base_url, 'https://unknown-host/unknown-stage')
    
    def test_extract_path_parameters_simple(self):
        """Test extracting path parameters from simple event"""
        event = {
            'pathParameters': {'shortId': 'abc123'}
        }
        
        short_id, stage, tenant = extract_path_parameters(event)
        self.assertEqual(short_id, 'abc123')
        self.assertIsNone(stage)
        self.assertIsNone(tenant)
    
    def test_extract_path_parameters_proxy_simple(self):
        """Test extracting path parameters from simple proxy path"""
        event = {
            'pathParameters': {'proxy': 'abc123'}
        }
        
        short_id, stage, tenant = extract_path_parameters(event)
        self.assertEqual(short_id, 'abc123')
        self.assertIsNone(stage)
        self.assertIsNone(tenant)
    
    def test_extract_path_parameters_proxy_multitenant(self):
        """Test extracting path parameters from multi-tenant proxy path"""
        event = {
            'pathParameters': {
                'proxy': 'stage/prod/tenant/company1/shorten'
            }
        }
        
        short_id, stage, tenant = extract_path_parameters(event)
        self.assertIsNone(short_id)  # 'shorten' is not a shortId
        self.assertEqual(stage, 'prod')
        self.assertEqual(tenant, 'company1')
    
    def test_extract_path_parameters_empty(self):
        """Test extracting path parameters from empty event"""
        event = {}
        
        short_id, stage, tenant = extract_path_parameters(event)
        self.assertIsNone(short_id)
        self.assertIsNone(stage)
        self.assertIsNone(tenant)
    
    def test_parse_request_body_json_string(self):
        """Test parsing JSON string request body"""
        event = {
            'body': '{"longUrl": "https://example.com", "customSuffix": "test"}'
        }
        
        body = parse_request_body(event)
        self.assertEqual(body['longUrl'], 'https://example.com')
        self.assertEqual(body['customSuffix'], 'test')
    
    def test_parse_request_body_dict(self):
        """Test parsing dictionary request body"""
        event = {
            'body': {"longUrl": "https://example.com", "customSuffix": "test"}
        }
        
        body = parse_request_body(event)
        self.assertEqual(body['longUrl'], 'https://example.com')
        self.assertEqual(body['customSuffix'], 'test')
    
    def test_parse_request_body_invalid_json(self):
        """Test parsing invalid JSON raises JSONDecodeError"""
        event = {
            'body': '{"longUrl": "https://example.com", invalid}'
        }
        
        with self.assertRaises(json.JSONDecodeError):
            parse_request_body(event)
    
    def test_parse_request_body_missing(self):
        """Test parsing missing body raises ValueError"""
        event = {}
        
        with self.assertRaises(ValueError):
            parse_request_body(event)
    
    def test_parse_request_body_invalid_type(self):
        """Test parsing invalid body type raises ValueError"""
        event = {
            'body': 123  # Invalid type
        }
        
        with self.assertRaises(ValueError):
            parse_request_body(event)
    
    def test_create_json_response(self):
        """Test creating JSON response"""
        body = {'message': 'success', 'data': {'id': 123}}
        response = create_json_response(HTTP_STATUS_OK, body)
        
        self.assertEqual(response['statusCode'], HTTP_STATUS_OK)
        self.assertEqual(response['headers']['Content-Type'], 'application/json')
        self.assertIn('Access-Control-Allow-Origin', response['headers'])
        
        parsed_body = json.loads(response['body'])
        self.assertEqual(parsed_body['message'], 'success')
        self.assertEqual(parsed_body['data']['id'], 123)
    
    def test_create_json_response_with_additional_headers(self):
        """Test creating JSON response with additional headers"""
        body = {'message': 'success'}
        additional_headers = {'X-Custom-Header': 'custom-value'}
        
        response = create_json_response(HTTP_STATUS_OK, body, additional_headers)
        
        self.assertEqual(response['headers']['X-Custom-Header'], 'custom-value')
        self.assertEqual(response['headers']['Content-Type'], 'application/json')
    
    # HTML response test removed - using JSON-only approach
    
    def test_create_redirect_response(self):
        """Test creating redirect response"""
        location = 'https://example.com/redirected'
        response = create_redirect_response(location)
        
        self.assertEqual(response['statusCode'], 302)
        self.assertEqual(response['headers']['Location'], location)
        self.assertIn('Cache-Control', response['headers'])
        self.assertEqual(response['body'], '')
    
    def test_create_error_response(self):
        """Test creating error response with logging"""
        error_message = 'Test error message'
        
        # Note: In actual tests, you might want to mock the logger and metrics
        response = create_error_response(
            HTTP_STATUS_BAD_REQUEST,
            error_message,
            self.logger,
            self.metrics
        )
        
        self.assertEqual(response['statusCode'], HTTP_STATUS_BAD_REQUEST)
        parsed_body = json.loads(response['body'])
        self.assertEqual(parsed_body['error'], error_message)
    
    def test_get_current_timestamp(self):
        """Test getting current timestamp"""
        timestamp = get_current_timestamp()
        
        # Should be a valid ISO format timestamp
        parsed_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        self.assertIsInstance(parsed_time, datetime)
        
        # Should be recent (within 5 seconds)
        now = datetime.now(timezone.utc)
        time_diff = abs((parsed_time - now).total_seconds())
        self.assertLess(time_diff, 5)
    
    def test_lambda_error(self):
        """Test LambdaError exception"""
        error = LambdaError("Test error", HTTP_STATUS_BAD_REQUEST)
        
        self.assertEqual(error.message, "Test error")
        self.assertEqual(error.status_code, HTTP_STATUS_BAD_REQUEST)
        self.assertEqual(str(error), "Test error")
    
    def test_validation_error(self):
        """Test ValidationError exception"""
        error = ValidationError("Invalid input")
        
        self.assertEqual(error.message, "Invalid input")
        self.assertEqual(error.status_code, HTTP_STATUS_BAD_REQUEST)
    
    def test_not_found_error(self):
        """Test NotFoundError exception"""
        error = NotFoundError("Resource not found")
        
        self.assertEqual(error.message, "Resource not found")
        self.assertEqual(error.status_code, HTTP_STATUS_NOT_FOUND)
    
    def test_conflict_error(self):
        """Test ConflictError exception"""
        error = ConflictError("Resource conflict")
        
        self.assertEqual(error.message, "Resource conflict")
        self.assertEqual(error.status_code, HTTP_STATUS_CONFLICT)
    
    def test_constants_are_defined(self):
        """Test that HTTP status constants are properly defined"""
        self.assertEqual(HTTP_STATUS_OK, 200)
        self.assertEqual(HTTP_STATUS_CREATED, 201)
        self.assertEqual(HTTP_STATUS_BAD_REQUEST, 400)
        self.assertEqual(HTTP_STATUS_NOT_FOUND, 404)
        self.assertEqual(HTTP_STATUS_CONFLICT, 409)
        self.assertEqual(HTTP_STATUS_INTERNAL_ERROR, 500)


if __name__ == '__main__':
    unittest.main() 