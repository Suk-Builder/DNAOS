import urllib.request, gzip, struct, math, json, time, os

def hpix(nside, ipix):
    npix = 12*nside*nside
    if ipix<0 or ipix>=npix: return None,None
    nl2, nl4, ncap = 2*nside, 4*nside, 2*nside*(nside-1)
    if ipix<ncap:
        iring = int(math.isqrt((ipix//2)//nside))+1
        iphi = ipix+1-2*nside*(iring-1)*iring
        z = 1.0-(iring*iring)/(3.0*nside*nside)
        phi = (iphi-0.5)*math.pi/(2.0*nside*iring)
    elif ipix<nl2*(5*nside-1):
        ip=ipix-ncap; iring=ip//nl4+nside; iphi=ip%nl4+1
        fodd=0.5*(1+((iring+nside)%2))
        z=(nl2-iring)/(1.5*nside); phi=(iphi-fodd)*math.pi/(2.0*nside)
    else:
        ip=npix-ipix; hip=ip//2
        iring=int(math.isqrt(hip//nside))+1
        iphi=4*iring+1-(ip-2*nside*(iring-1)*iring)
        z=-1.0+(iring*iring)/(3.0*nside*nside)
        phi=(iphi-0.5)*math.pi/(2.0*nside*iring)
    return math.acos(max(-1.0,min(1.0,z))),phi

def ang2radec(t,p): return (math.degrees(p)%360.0, 90.0-math.degrees(t))

def extract(url):
    req=urllib.request.Request(url,headers={'User-Agent':'gwosc-python/0.8.2'})
    with urllib.request.urlopen(req,timeout=60) as r:
        with open('/tmp/s.gz','wb') as f:
            while True:
                chunk=r.read(1024*1024)
                if not chunk: break
                f.write(chunk)
    with open('/tmp/s.gz','rb') as f:
        with open('/tmp/s.fits','wb') as o:
            d=gzip.GzipFile(fileobj=f)
            while True:
                chunk=d.read(1024*1024)
                if not chunk: break
                o.write(chunk)
    with open('/tmp/s.fits','rb') as f: data=f.read()
    pos=0
    for _ in range(10):
        hs=pos; he=False
        while pos<len(data):
            if b'END' in data[pos:pos+2880]: he=True; pos+=2880; break
            pos+=2880
        if not he: break
        hdr=data[hs:pos].decode('ascii',errors='replace')
        nside=None; bitpix=8; naxis=0; naxis_list=[]; tform=[]
        for i in range(0,len(hdr),80):
            c=hdr[i:i+80]; kw=c[:8].strip()
            try:
                if kw=='NSIDE': nside=int(c[c.index('=')+1:].split('/')[0].strip())
                elif kw=='BITPIX': bitpix=int(c[c.index('=')+1:].split('/')[0].strip())
                elif kw=='NAXIS': naxis=int(c[c.index('=')+1:].split('/')[0].strip())
                elif kw.startswith('NAXIS') and kw[5:].isdigit(): naxis_list.append(int(c[c.index('=')+1:].split('/')[0].strip()))
                elif kw.startswith('TFORM'): tform.append(c[c.index('=')+1:].split('/')[0].strip().strip("'").strip())
            except: pass
        if nside:
            bpv=abs(bitpix)//8; ds=1
            for n in naxis_list: ds*=n
            ds=((ds+2879)//2880)*2880
            hd=data[pos:pos+ds]
            rs=sum(8 if f=='D' else 4 if f=='E' else 8 for f in tform)
            npix=naxis_list[1] if len(naxis_list)>1 else (12*nside*nside)
            mp,pp=-1,0
            for ii in range(npix):
                p=struct.unpack_from('>d',hd,ii*rs)[0]
                if p>mp: mp,pp=p,ii
            th,ph=hpix(nside,pp)
            return {'peak_ra':ang2radec(th,ph)[0],'peak_dec':ang2radec(th,ph)[1],'nside':nside}
        if naxis>0:
            ds=1
            for n in naxis_list: ds*=n
            ds=((ds+2879)//2880)*2880
            pos+=ds
    return None

events=[
('GW170817','S170817'),('GW191219_163120','S191219ap'),('GW190814','S190814bv'),
('GW200210_092254','S200210co'),('GW191113_071753','S191113u'),('GW190929_012149','S190929d'),
('GW200115_042309','S200115j'),('GW190412','S190412m'),('GW200208_222617','S200208dg'),
('GW151012','S151012'),('GW200216_220804','S200216br'),('GW170104','S170104'),
('GW190828_065509','S190828l'),
]

results=[]
for name,gid in events:
    url=f'https://gracedb.ligo.org/apiweb/superevents/{gid}/files/bayestar.fits.gz'
    for _ in range(3):
        try:
            r=extract(url)
            if r:
                ra_h=r['peak_ra']/15.0; ra_m=(ra_h-int(ra_h))*60
                dsgn='+' if r['peak_dec']>=0 else ''
                print(f'{name:25s} RA={r["peak_ra"]:7.2f} ({int(ra_h):02d}h{int(ra_m):02d}m) DEC={dsgn}{r["peak_dec"]:6.2f} NSIDE={r["nside"]}')
                results.append({'name':name,'gid':gid,**r})
                break
        except Exception as e:
            print(f'{name} retry...')
        time.sleep(1)
    time.sleep(0.5)

with open('/mnt/agents/output/gw_data/crack_sky_positions.json','w') as f:
    json.dump(results,f,indent=2)
print(f'\nDone: {len(results)}/13')
