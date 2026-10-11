// npm install --prefix /private/tmp/devutils-formatter-vendors --ignore-scripts js-beautify@1.15.4 html-minifier@4.0.0 csso@5.0.5 esbuild@0.25.10
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const modules = process.argv[2] || '/private/tmp/devutils-formatter-vendors/node_modules';
require(path.join(modules, 'esbuild')).buildSync({
  entryPoints: [path.join(__dirname, 'vendor_entry.cjs')],
  nodePaths: [modules],
  bundle: true,
  alias: Object.fromEntries(['clean-css', 'uglify-js', 'relateurl'].map(name => [name, path.join(__dirname, 'disabled_vendor.cjs')])),
  platform: 'browser',
  format: 'iife',
  globalName: 'DevutilsFormatters',
  outfile: path.join(root, 'assets/javascript/formatter-vendors.js'),
  minify: true,
  legalComments: 'eof',
});
// Retain licenses for every package contributing source to the bundle.
const licenses = [];
for (const name of fs.readdirSync(modules)) {
  if (name.startsWith('.') || name.startsWith('@')) continue;
  const dir = path.join(modules, name);
  const filename = fs.readdirSync(dir).find(n => /^licen[sc]e(\.|$)/i.test(n));
  if (filename) licenses.push(name + '\n' + fs.readFileSync(path.join(dir, filename), 'utf8'));
}
fs.writeFileSync(path.join(root, 'assets/javascript/FORMATTER-LICENSES.txt'), licenses.join('\n\n----------------\n\n'));
