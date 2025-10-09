#!/bin/bash
set -x
set -e
set -o pipefail

if [ -f ".venv/bin/activate" ]; then
    echo "Activating virtual environment..."
    source .venv/bin/activate
else
    echo "Virtual environment not found. Creating and setting it up..."
    python3 -m venv .venv
    source .venv/bin/activate
    pip3 install -r src/requirements.txt
fi

# Set environment variables
export AWS_REGION="us-west-2"
export AWS_PROFILE="hireko"
export ENVIRONMENT="beta"
export AWS_CONFIGURATION_REGION="us-east-1"
export PYTHONBREAKPOINT="pdb.set_trace"

# Set PYTHONPATH to include src and test directories
export PYTHONPATH="${PWD}/src:${PWD}/test:./src:./test"

# Run all unit tests in the test directory
echo "Running all unit tests with verbose output..."
echo "=========================================="

# Run tests with verbose output and capture both stdout and stderr
if python3 -m unittest discover -s test -p "test_*.py" -v 2>&1; then
    echo "=========================================="
    echo "✅ All tests passed successfully!"
else
    echo "=========================================="
    echo "❌ TESTS FAILED - Build will not continue"
    echo "=========================================="
    echo "Test execution failed with exit code: $?"
    echo "Check the output above for detailed error information."
    echo "=========================================="
    exit 1
fi 
