"""
FastAPI middleware and dependency injection.

The auth middleware provides FastAPI dependencies for:
- Extracting the current user from JWT tokens
- Checking specific permissions
- Requiring PIN verification for sensitive ops
"""
