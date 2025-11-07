FROM python:3.11-slim

# Install required Python packages
RUN pip install requests PyJWT

# Copy the authentication middleware
COPY auth_middleware.py /app/auth_middleware.py

# Set working directory
WORKDIR /app

# Expose the port
EXPOSE 4319

# Run the middleware
CMD ["python", "auth_middleware.py"]