import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from fastapi.responses import Response
import v2_bridge
@pytest.fixture
def client(monkeypatch):
 monkeypatch.setenv("INGEST_KEY","bridge-test-key");app=FastAPI();app.include_router(v2_bridge.router);return TestClient(app)
def test_auth_before_forward(client,monkeypatch):
 monkeypatch.setattr(v2_bridge,"forward",lambda *a:pytest.fail("unauthorized forwarded"))
 assert client.post('/v2/events',json={},headers={"X-API-Key":"bad"}).status_code==401
def test_exact_body(client,monkeypatch):
 seen=[]
 def forward(path,data):seen.append((path,data));return Response(b'{}',status_code=202,media_type="application/json")
 monkeypatch.setattr(v2_bridge,"forward",forward);body=b'{"event_id":"stable-id"}'
 assert client.post('/v2/events',content=body,headers={"X-API-Key":"bridge-test-key"}).status_code==202
 assert seen==[("/v2/events",body)]
def test_size(client):
 assert client.post('/v2/events',content=b'x'*16385,headers={"X-API-Key":"bridge-test-key"}).status_code==413
