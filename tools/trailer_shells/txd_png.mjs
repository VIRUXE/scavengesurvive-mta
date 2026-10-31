// Decodes every texture of a TXD to <out>/<texture>.png with gta-scout's TXDReader (C:/dev/gta/sa/tools/gta-scout).
//     node tools/trailer_shells/txd_png.mjs IN.txd OUT_DIR
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

const SCOUT = process.env.GTA_SCOUT || 'C:/dev/gta/sa/tools/gta-scout';
const {TXDReader} = await import(pathToFileURL(path.resolve(SCOUT, 'shared/TXDReader.js')).href);
const {PNG} = createRequire(path.resolve(SCOUT, 'package.json'))('pngjs');
const [src, out] = process.argv.slice(2);
fs.mkdirSync(out, {recursive: true});
const bytes = fs.readFileSync(src);
const txd = new TXDReader().parse(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
for (const t of txd.textures) {
  const png = new PNG({width: t.width, height: t.height});
  png.data = Buffer.from(t.imageData);
  fs.writeFileSync(path.join(out, t.name.toLowerCase() + '.png'), PNG.sync.write(png));
}
console.log(`${txd.textures.length} textures -> ${out}`);
