import logging
import os
from flask import Flask, jsonify

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

app = Flask(__name__)
hostname = os.uname()[1]

@app.route("/")
def index():
    logging.info("Backend (%s): / called", hostname)
    return jsonify(
        message="Welcome to the Backend API",
        hostname=hostname,
        service="backend-service",
    )

@app.route("/api/data")
def get_data():
    logging.info("Backend (%s): /api/data called", hostname)
    return jsonify(
        message="Successfully retrieved data from backend",
        data={"item_id": 123, "description": "Some important data", "value": 42},
        source_hostname=hostname,
    )

@app.route("/health")
def health_check():
    logging.debug("Backend (%s): /health called", hostname)
    return jsonify(status="ok", service="backend-service", hostname=hostname), 200
