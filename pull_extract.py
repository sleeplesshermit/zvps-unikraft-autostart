import json, os, subprocess, sys, urllib.request

REG='https://ghcr.io/v2/zv201413/zvps'
tok=json.loads(urllib.request.urlopen('https://ghcr.io/token?service=ghcr.io&scope=repository:zv201413/zvps:pull').read())['token']
def get(url, accept=None):
    r=urllib.request.Request(url, headers={'Authorization':f'Bearer {tok}', **({'Accept':accept} if accept else {})})
    return urllib.request.urlopen(r)
man=json.loads(get(f'{REG}/manifests/latest','application/vnd.docker.distribution.manifest.v2+json').read())
rootfs='rootfs'; os.makedirs(rootfs, exist_ok=True)
tmp='layer_tmp'
for i,layer in enumerate(man['layers']):
    dg=layer['digest']; fn=f'blobs/{dg.replace(":","_")}.tar.gz'
    os.makedirs('blobs', exist_ok=True)
    if not os.path.exists(fn):
        with get(f'{REG}/blobs/{dg}') as resp, open(fn,'wb') as f:
            while True:
                chunk=resp.read(1<<20)
                if not chunk: break
                f.write(chunk)
    subprocess.run(['rm','-rf',tmp]); os.makedirs(tmp)
    subprocess.run(['tar','--numeric-owner','-xzf',fn,'-C',tmp], check=True)
    # apply whiteouts
    for dirpath, dirnames, filenames in os.walk(tmp):
        for name in filenames+dirnames:
            if name=='.wh..wh..opq':
                rel=os.path.relpath(dirpath,tmp); target=os.path.join(rootfs,rel)
                if os.path.isdir(target):
                    for child in os.listdir(target):
                        subprocess.run(['rm','-rf',os.path.join(target,child)])
            elif name.startswith('.wh.'):
                rel=os.path.relpath(os.path.join(dirpath,name[4:]),tmp)
                subprocess.run(['rm','-rf',os.path.join(rootfs,rel)])
    subprocess.run(f'cp -a {tmp}/. {rootfs}/ && find {tmp} -name ".wh.*" -delete', shell=True)
    print(f'layer {i+1}/{len(man["layers"])} done', flush=True)
subprocess.run(['rm','-rf',tmp])
print('rootfs extracted')
