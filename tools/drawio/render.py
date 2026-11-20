# draw.io 원본(.drawio)을 PNG(2배 해상도)로 렌더링한다 — render.sh 가 부른다
import sys, json, asyncio, pathlib, html
from playwright.async_api import async_playwright
from PIL import Image, ImageChops
PORT = sys.argv[1]; FILES = sys.argv[2:]
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=None if not pathlib.Path('/usr/bin/google-chrome').exists() else '/usr/bin/google-chrome',
                                    args=['--no-sandbox', '--no-proxy-server'])
        pg = await b.new_page(device_scale_factor=2, viewport={'width': 1800, 'height': 1400})
        work = pathlib.Path(__file__).parent / '.work'
        for f in FILES:
            cfg = json.dumps({"xml": pathlib.Path(f).read_text(), "toolbar": "", "lightbox": False, "nav": False, "border": 20})
            (work / 'page.html').write_text(f'<html><body style="margin:0;background:#fff"><div id="d" class="mxgraph" style="width:1700px;min-height:200px" '
                                            f'data-mxgraph="{html.escape(cfg)}"></div><script src="viewer-static.min.js"></script></body></html>')
            await pg.goto(f'http://127.0.0.1:{PORT}/page.html')
            await pg.wait_for_selector('#d svg', timeout=30000); await pg.wait_for_timeout(1500)
            out = f[:-len('.drawio')] + '.png'
            await (await pg.query_selector('#d svg')).screenshot(path=out)
            im = Image.open(out).convert('RGB'); bb = ImageChops.difference(im, Image.new('RGB', im.size, (255, 255, 255))).getbbox()
            im.crop((max(bb[0]-30, 0), max(bb[1]-30, 0), bb[2]+30, bb[3]+30)).save(out)
            print('✅', out)
        await b.close()
asyncio.run(main())
