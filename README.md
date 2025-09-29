# URL Shortener Service

A serverless URL shortener service built with AWS Lambda, API Gateway, DynamoDB, and Terraform, following Hireko company standards.

## Features

- **Create Short URLs**: Convert long URLs into short, manageable links
- **TTL Support**: URLs expire after 60 days for security
- **Custom Suffixes**: Option to create custom short URL suffixes
- **Redirect Service**: Fast redirection with click tracking
- **Serverless Architecture**: Built on AWS Lambda for scalability
- **Infrastructure as Code**: Complete Terraform configuration
- **CI/CD Pipeline**: Azure DevOps pipeline for automated deployments

## Architecture

```
Client Request → API Gateway → Lambda Functions → DynamoDB
                     ↓
              CloudWatch Logs & Metrics
```

### Components

- **API Gateway**: RESTful API endpoints
- **Lambda Functions**: 
  - `getOrCreateShortURL`: Creates or retrieves short URLs
  - `redirectURL`: Handles URL redirection
- **DynamoDB**: Stores URL mappings with TTL
- **CloudWatch**: Logging and monitoring

## API Endpoints

### Create/Get Short URL
```http
POST /shorten
Content-Type: application/json

{
  "longUrl": "https://example.com/very/long/url",
  "customSuffix": "optional-custom-suffix"  // optional
}
```

**Response:**
```json
{
  "shortUrl": "https://api-id.execute-api.region.amazonaws.com/env/abc123",
  "longUrl": "https://example.com/very/long/url",
  "expiryDate": "2024-03-15T10:30:00",
  "created": true
}
```

### Redirect URL
```http
GET /{shortId}
```

Returns a 302 redirect to the original URL or appropriate error pages.

## Project Structure

```
UrlShortner/
├── src/
│   ├── commons/
│   │   └── url_utils.py          # URL utility functions
│   ├── url_shortener_handlers/
│   │   ├── getOrCreateShortURL.py # Create/get short URL handler
│   │   └── redirectURL.py        # Redirect handler
│   └── requirements.txt          # Python dependencies
├── infra/
│   ├── terraform/
│   │   ├── main.tf              # Main Terraform configuration
│   │   ├── variables.tf         # Terraform variables
│   │   ├── dynamodb.tf          # DynamoDB table and IAM
│   │   ├── lambdas/             # Lambda module
│   │   └── api_gateway/         # API Gateway module
│   └── deploy_utils.sh          # Deployment utilities
├── test/
│   └── test_url_utils.py        # Unit tests
├── pipelines/
│   └── azure-pipelines.yml      # CI/CD pipeline
├── z_setup_deploy_beta.sh       # Beta deployment script
├── z_setup_deploy_prod.sh       # Production deployment script
└── README.md                    # This file
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Python 3.10+
- Azure DevOps (for CI/CD)

## Local Development

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd UrlShortner
   ```

2. **Install dependencies:**
   ```bash
   pip install -r src/requirements.txt
   ```

3. **Run tests:**
   ```bash
   python -m unittest discover -s test -p "test_*.py" -v
   ```

## Deployment

### Beta Environment
```bash
./z_setup_deploy_beta.sh
```

### Production Environment
```bash
./z_setup_deploy_prod.sh
```

The deployment scripts will:
1. Run unit tests
2. Package Lambda functions
3. Initialize Terraform
4. Deploy infrastructure
5. Generate output file with API endpoints

## Environment Variables

The Lambda functions use these environment variables (set by Terraform):

- `PROJECT_NAME`: Name of the project
- `ENVIRONMENT`: Deployment environment (beta/prod)
- `DYNAMODB_TABLE_NAME`: DynamoDB table name
- `DYNAMODB_TABLE_ARN`: DynamoDB table ARN
- `BASE_URL`: Base URL for short links

## DynamoDB Schema

### URLMappings Table
- **Partition Key**: `shortId` (String)
- **Attributes**:
  - `longUrl` (String): Original URL
  - `createdAt` (String): ISO timestamp
  - `expiryDate` (String): ISO timestamp
  - `clickCount` (Number): Number of clicks
  - `lastAccessedAt` (String): ISO timestamp
- **GSI**: `longUrl-index` for duplicate detection
- **TTL**: `ttlTimestamp` for automatic cleanup

## Security Features

- **URL Validation**: Strict validation of input URLs
- **TTL Expiration**: URLs expire after 60 days
- **CORS Support**: Proper CORS headers for web clients
- **Error Handling**: Comprehensive error responses
- **Logging**: Detailed CloudWatch logging with AWS Powertools

## Monitoring

The service includes comprehensive monitoring:

- **CloudWatch Logs**: All Lambda executions logged
- **CloudWatch Metrics**: Custom metrics for operations
- **AWS X-Ray**: Distributed tracing (via Powertools)
- **Error Tracking**: Failed requests and exceptions

## Cost Optimization

- **Pay-per-request DynamoDB**: Only pay for actual usage
- **Lambda concurrency**: Automatic scaling
- **TTL cleanup**: Automatic deletion of expired URLs
- **Regional deployment**: Reduced latency and costs

## Contributing

1. Follow the existing code structure
2. Add unit tests for new functionality
3. Update documentation as needed
4. Test deployments in beta before production

## License

This project follows Hireko company licensing standards. 