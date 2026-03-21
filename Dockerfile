# Use a specific version for stability
FROM python:3.11-slim-bookworm

# Install only what's needed for nmcli and dbus communication
RUN apt-get update && apt-get install -y \
    network-manager \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy your script
COPY manager.py .

# Run the script
CMD ["python3", "main.py"]