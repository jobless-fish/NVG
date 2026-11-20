import json,tempfile,threading,unittest,uuid
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from client import Client,sample,validate
class Handler(BaseHTTPRequestHandler):
    seen=[];fail_once=False;block=False
    def log_message(self,*args):pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers["Content-Length"])));Handler.seen.append((self.path,body,self.headers.get("Authorization")))
        status=201;result={}
        if self.headers.get("Authorization")!="Bearer test-key":status=401
        elif Handler.block:status=400
        elif Handler.fail_once:status=503;Handler.fail_once=False
        elif self.path.endswith("player-login"):result={"player":{"player_id":"22222222-2222-4222-8222-222222222222"},"created":True}
        else:result={"record_id":body["data"]["id"],"created":True}
        self.send_response(status);self.send_header("Content-Type","application/json");self.end_headers();self.wfile.write(json.dumps(result).encode())
class TestClient(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.server=ThreadingHTTPServer(("127.0.0.1",0),Handler);threading.Thread(target=cls.server.serve_forever,daemon=True).start();cls.base="http://127.0.0.1:"+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):cls.server.shutdown();cls.server.server_close()
    def setUp(self):Handler.seen=[];Handler.fail_once=False;Handler.block=False
    def test_mapping_order_retry_restart(self):
        with tempfile.TemporaryDirectory() as d:
            c=Client(d);manifest=sample();c.enqueue(manifest);Handler.fail_once=True
            self.assertEqual(c.flush(self.base,"test-key")["state"],"sent")
            self.assertEqual(Handler.seen[0][1],Handler.seen[1][1])
            session=next(x[1] for x in Handler.seen if x[1].get("record_type")=="session")
            self.assertEqual(session["data"]["player_id"],"22222222-2222-4222-8222-222222222222")
            c.db.close();c=Client(d);before=len(Handler.seen);c.flush(self.base,"test-key");self.assertEqual(before,len(Handler.seen));c.db.close()
    def test_400_blocks_following(self):
        with tempfile.TemporaryDirectory() as d:
            c=Client(d);c.enqueue(sample());Handler.block=True;self.assertEqual(c.flush(self.base,"test-key")["state"],"blocked");self.assertEqual(len(Handler.seen),1);c.db.close()
    def test_401_blocks_and_problem_id_stable(self):
        self.assertEqual(sample()[1]["body"]["data"]["id"],sample()[1]["body"]["data"]["id"])
        with tempfile.TemporaryDirectory() as d:
            c=Client(d);c.enqueue(sample());result=c.flush(self.base,"wrong");self.assertEqual(result["status"],401);self.assertEqual(len(Handler.seen),1);c.db.close()
    def test_validation(self):
        m=sample()
        for x in m:validate(x["path"],x["body"])
        m[-1]["body"]["data"]["sequence"]=0
        with self.assertRaises(ValueError):validate(m[-1]["path"],m[-1]["body"])
        with self.assertRaises(ValueError):validate("/api/game/player-login",{"member_id":"x","display_name":"x","password":"bad"})
        m=sample();m[-1]["body"]["data"]["payload"]={"nested":{"authorization":"bad"}}
        with self.assertRaises(ValueError):validate(m[-1]["path"],m[-1]["body"])
if __name__=="__main__":unittest.main()
