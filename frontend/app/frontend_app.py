import logging
import os
import requests
from flask import Flask, jsonify, render_template_string

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

app = Flask(__name__)
hostname = os.uname()[1]

BACKEND_SERVICE_URL = os.getenv("BACKEND_URL", "http://localhost:9191")  # ← changed

@app.route("/")
def home():
    logging.info("Frontend (%s): / called", hostname)
    backend_data = error_message = None
    status_code = 200

    try:
        target_url = f"{BACKEND_SERVICE_URL}/api/data"
        logging.info("Frontend (%s): querying backend at %s", hostname, target_url)
        resp = requests.get(target_url, timeout=5)
        resp.raise_for_status()
        backend_data = resp.json()
    except requests.exceptions.RequestException as err:
        error_message = str(err)
        status_code = getattr(err.response, "status_code", 503)
        logging.error("Frontend (%s): backend request failed – %s", hostname, error_message)

    html_template = """<!DOCTYPE html><html><head><title>Frontend</title></head><body>
        <h1>Frontend Service</h1>
        <p>Host: {{ hostname }}</p>
        <h2>Backend Data:</h2>
        {% if error_message %}
            <p style="color:red;">Error ({{ status_code }}): {{ error_message }}</p>
        {% elif backend_data %}
            <pre>{{ backend_data | tojson(indent=4) }}</pre>
        {% else %}
            <p>No data received.</p>
        {% endif %}
    </body></html>"""
    return render_template_string(
        html_template,
        hostname=hostname,
        backend_data=backend_data,
        error_message=error_message,
        status_code=status_code,
    ), status_code

@app.route("/health")
def health():
    return jsonify(status="ok", service="frontend", hostname=hostname), 200
