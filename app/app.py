"""Visitor Counter - Flask + Redis."""
import os
import socket
import time

import redis
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT_NUMBER", "6379"))
CLUSTER_NAME = os.getenv("CLUSTER_NAME", "local")

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT,
                socket_connect_timeout=2, socket_timeout=2,
                decode_responses=True)

PAGE = """<!doctype html>
<title>Visitor Counter</title>
<body style="font-family:system-ui;max-width:560px;margin:60px auto;text-align:center">
<h1>Visitor Counter</h1>
<p style="font-size:64px;margin:10px">{{ count }}</p>
<p>Served by pod <b>{{ pod }}</b></p>
<p>Cluster: <b>{{ cluster }}</b></p>
</body>"""


@app.route("/")
def index():
    try:
        count = r.incr("visits")
    except redis.RedisError:
        return "Redis unavailable", 503
    return render_template_string(PAGE, count=count,
                                  pod=socket.gethostname(), cluster=CLUSTER_NAME)


@app.route("/api/count")
def api_count():
    try:
        return jsonify(count=int(r.get("visits") or 0),
                       pod=socket.gethostname(), cluster=CLUSTER_NAME)
    except redis.RedisError:
        return jsonify(error="redis unavailable"), 503


@app.route("/healthz")  # liveness: process is up
def healthz():
    return "ok", 200


@app.route("/ready")  # readiness: can reach Redis
def ready():
    try:
        r.ping()
        return "ready", 200
    except redis.RedisError:
        return "redis not reachable", 503


@app.route("/load")  # CPU burner used to trigger the HPA
def load():
    end = time.time() + 0.05
    x = 0
    while time.time() < end:
        x += 1
    return "burned", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
