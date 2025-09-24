#!/usr/bin/env python3
import json, random, time, argparse, datetime
from hashlib import blake2b

p = argparse.ArgumentParser()
p.add_argument("--n", type=int, default=200000, help="Quantidade de documentos")
p.add_argument("--dims", type=int, default=128, help="Dimensão do vetor")
args = p.parse_args()

services = ["api-gateway","checkout","payment","auth","catalog"]
actions  = [f"a{i}" for i in range(1,201)]

for i in range(args.n):
    svc = random.choice(services)
    act = random.choice(actions)
    usr = f"u{random.randint(1,50000)}"
    msg = f"event {i} service={svc} user={usr} action={act}"
    h = blake2b((msg+str(i)).encode(), digest_size=8).hexdigest()
    doc = {
      "@timestamp": (datetime.datetime.utcnow() - datetime.timedelta(seconds=random.randint(0, 172800))).isoformat() + "Z",
      "service": svc,
      "level": random.choice(["INFO","WARN","ERROR"]),
      "message": msg,
      "req_id": h,
      "latency_ms": random.randint(1, 2500),
      "embedding": [random.uniform(-1,1) for _ in range(args.dims)]
    }
    print(json.dumps({"index":{}}))
    print(json.dumps(doc))
