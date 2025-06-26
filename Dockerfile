# Use Ubuntu as base image
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV DISPLAY=:99

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    wget \
    curl \
    unzip \
    xvfb \
    x11vnc \
    fluxbox \
    supervisor \
    cron \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create directories and log files
RUN mkdir -p /app /etc/reward /var/log/supervisor \
    && touch /var/log/rewards-farmer.log \
    && chmod 666 /var/log/rewards-farmer.log

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create entrypoint script with random delay
RUN cat > /app/entrypoint.sh << 'EOF'
#!/bin/bash

# Start Xvfb
Xvfb :99 -screen 0 1920x1080x24 &

# Wait for Xvfb to start
sleep 2

# Add random delay between 0-10 minutes (0-600 seconds)
RANDOM_DELAY=$((RANDOM % 600))
echo "$(date): Waiting for $RANDOM_DELAY seconds before starting..." | tee -a /var/log/rewards-farmer.log
sleep $RANDOM_DELAY

# Start the Python script
echo "$(date): Starting Microsoft Rewards Farmer..." | tee -a /var/log/rewards-farmer.log
cd /app
python3 main.py "$@" 2>&1 | tee -a /var/log/rewards-farmer.log
echo "$(date): Microsoft Rewards Farmer completed." | tee -a /var/log/rewards-farmer.log
EOF

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Create cron job for daily execution at 9:30 AM with random delay
RUN cat > /etc/cron.d/rewards-farmer << 'EOF'
# Microsoft Rewards Farmer - Daily execution with random delay
# Runs at 9:20-9:40 AM (9:30 ± 10 minutes) every day
20-40 9 * * * root /app/entrypoint.sh >> /var/log/rewards-farmer.log 2>&1
EOF

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/rewards-farmer

# Create supervisor configuration
RUN cat > /etc/supervisor/conf.d/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root

[program:cron]
command=/usr/sbin/cron -f
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/cron.err.log
stdout_logfile=/var/log/supervisor/cron.out.log

[program:xvfb]
command=Xvfb :99 -screen 0 1920x1080x24
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/xvfb.err.log
stdout_logfile=/var/log/supervisor/xvfb.out.log
EOF

# Expose port for VNC (optional, for debugging)
EXPOSE 5900

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ps aux | grep -q '[s]upervisord' || exit 1

# Set the entrypoint
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
