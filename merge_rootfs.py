import json, os, tarfile, urllib.request

REG='https://ghcr.io/v2/zv201413/zvps'
tok=json.loads(urllib.request.urlopen('https://ghcr.io/token?service=ghcr.io&scope=repository:zv201413/zvps:pull').read())['token']
man=json.loads(urllib.request.urlopen(urllib.request.Request(f'{REG}/manifests/latest', headers={'Authorization':f'Bearer {tok}','Accept':'application/vnd.docker.distribution.manifest.v2+json'})).read())
os.makedirs('blobs', exist_ok=True)
layer_files=[]
for layer in man['layers']:
    dg=layer['digest']; fn=f'blobs/{dg.replace(":","_")}.tar.gz'
    if not os.path.exists(fn):
        req=urllib.request.Request(f'{REG}/blobs/{dg}', headers={'Authorization':f'Bearer {tok}'})
        with urllib.request.urlopen(req) as resp, open(fn,'wb') as f:
            while True:
                c=resp.read(1<<20)
                if not c: break
                f.write(c)
    layer_files.append(fn)
print('layers downloaded:', len(layer_files), flush=True)

def norm(name):
    n=name.strip('./')
    return n

# Pass 1: survivor map path -> layer index
survivor={}
for li, fn in enumerate(layer_files):
    with tarfile.open(fn,'r:gz') as tf:
        for m in tf:
            n=norm(m.name)
            if not n: continue
            base=os.path.basename(n); d=os.path.dirname(n)
            if base=='.wh..wh..opq':
                for p in list(survivor):
                    if p.startswith(n.rstrip('/')[:-len('.wh..wh..opq')] if False else (d+'/' if d else '')) and survivor[p]<li:
                        del survivor[p]
                continue
            if base.startswith('.wh.'):
                target=(d+'/'+base[4:]) if d else base[4:]
                for p in list(survivor):
                    if p==target or p.startswith(target+'/'):
                        del survivor[p]
                continue
            if not m.isdir():
                for p in list(survivor):
                    if p.startswith(n+'/'):
                        del survivor[p]
            survivor[n]=li
print('surviving paths:', len(survivor), flush=True)

# Pass 2: write merged tar
written=0
with tarfile.open('rootfs-merged.tar','w') as out:
    for li, fn in enumerate(layer_files):
        with tarfile.open(fn,'r:gz') as tf:
            for m in tf:
                n=norm(m.name)
                if not n or survivor.get(n)!=li: continue
                base=os.path.basename(n)
                if base.startswith('.wh.'): continue
                m.name=n
                if m.isfile():
                    src=tf.extractfile(m)
                    out.addfile(m, src)
                else:
                    out.addfile(m)
                written+=1
print('entries written:', written)
