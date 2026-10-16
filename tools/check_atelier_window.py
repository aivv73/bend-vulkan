#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from check_window import X11, states, isolated_display, build_window, BUILD, ROOT

COMPILE_TIMEOUT=1800


def run(binary, split):
    suffix='split' if split else 'shared'
    path=BUILD/f'milestone-6-atelier-window-{suffix}.log'
    x=X11()
    env=dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1',
             ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
    with path.open('w') as output:
        process=subprocess.Popen([str(binary),'--trace',*(['--split'] if split else [])],cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT)

        def wait(predicate,label,timeout=20):
            end=time.monotonic()+timeout
            while time.monotonic()<end:
                assert process.poll() is None, path.read_text()[-6000:]
                current=states(path)
                if current and predicate(current[-1]): return current[-1]
                time.sleep(.04)
            raise AssertionError(label+'\n'+path.read_text()[-5000:])

        def settled(previous):
            return wait(lambda s:s['frame']>previous['frame']+2 and s['installed']==s['revision'],'settled latest revision')

        def capture(name):
            from PIL import Image
            file=BUILD/f'milestone-6-atelier-window-{suffix}-{name}.png'
            subprocess.run(['import','-window',str(x.owned),str(file)],check=True,timeout=10)
            image=Image.open(file).convert('RGB')
            assert len(image.getcolors(image.width*image.height) or [])>3
            return image.tobytes()

        try:
            end=time.monotonic()+15
            while not x.find(process.pid):
                assert process.poll() is None,path.read_text()[-5000:]
                assert time.monotonic()<end,'default Atelier window missing'
                time.sleep(.04)
            x.focus();x.move(292,210)
            initial=wait(lambda s:s['frame']>=4 and s['uploads']==2 and s['installed']==0,'actual Atelier initial presentation')
            intact=capture('intact')
            x.button(1,1);x.button(1,0)
            carved=settled(wait(lambda s:s['revision']==1 and s['uploads']==4,'actual Atelier click edit'))
            cut=capture('carved');assert cut!=intact
            assert carved['quads']!=initial['quads']
            x.tap(ord('r'))
            reset=settled(wait(lambda s:s['revision']==2 and s['uploads']==6,'selected original Atelier reset'))
            assert reset['quads']==initial['quads']
            assert capture('reset')==intact
            x.tap(32)
            space=settled(wait(lambda s:s['revision']==3 and s['uploads']==8,'Space must cut current Atelier hover'))
            assert capture('space')==cut
            assert space['quads']==carved['quads']
            x.tap(ord('r')); restored=settled(wait(lambda s:s['revision']==4,'second reset'))
            x.key(ord('w'),1);time.sleep(.12);x.key(ord('w'),0)
            flown=settled(wait(lambda s:s['camera']!=restored['camera'],'Atelier flight'))
            assert flown['uploads']==restored['uploads']
            x.move(320,240);x.button(3,1)
            wait(lambda s:s['captured']==1,'Atelier pointer capture')
            os.kill(process.pid,signal.SIGSTOP)
            try:x.moves([(332,243),(342,249)])
            finally:os.kill(process.pid,signal.SIGCONT)
            looked=wait(lambda s:s['camera']!=flown['camera'],'Atelier captured look')
            x.button(3,0);settled(wait(lambda s:s['captured']==0,'Atelier capture release'))
            capture('flight-look')
            previous=looked
            for w,h in [(800,450),(450,900),(640,480)]:
                x.resize(w,h)
                previous=wait(lambda s:s['width']==w and s['height']==h and s['generation']>previous['generation'] and s['frame']>previous['frame']+2,'Atelier target recreation')
                assert previous['uploads']==restored['uploads'],'Resize uploaded geometry'
                capture(f'{w}x{h}')
            x.map(False)
            asleep=wait(lambda s:s['mapped']==0,'Atelier suspension')
            time.sleep(.2)
            assert states(path)[-1]['frame']<=asleep['frame']+1
            x.map(True);remapped=wait(lambda s:s['mapped']==1 and s['frame']>asleep['frame']+2,'Atelier remap')
            capture('remapped')
            x.close();process.wait(timeout=15)
            result=path.read_text()
            assert process.returncode==0,result[-8000:]
            assert 'Native interactive shutdown rows=0' in result
            assert not any(marker in result for marker in ('Validation Error','SYNC-HAZARD','AddressSanitizer','runtime error:'))
            queues=re.search(r'Queues (\d+) (\d+)',result)
            assert queues and ((queues[1]!=queues[2]) if split else (queues[1]==queues[2]))
            values=states(path)
            steady=[s['rows'] for s in values if s['generation']>=1 and s['uploads']>=2]
            assert max(steady)-min(steady)<=8,'Atelier edit/resize resources grew'
            print(f'Actual default Atelier {suffix} edit/Space/reset/flight/capture/resize/suspend/remap/close passed')
        finally:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait()
            x.x.XCloseDisplay(x.d)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path)
    parser.add_argument('--sanitize',action='store_true')
    parser.add_argument('--isolated-display',action='store_true')
    args=parser.parse_args()
    binary=args.binary.resolve() if args.binary else build_window(args.sanitize,compile_timeout=COMPILE_TIMEOUT)
    with isolated_display(args.isolated_display):
        for split in (False,True):run(binary,split)


if __name__=='__main__':main()
