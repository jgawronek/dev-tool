const fs = require('fs');
const vm = require('vm');
const context = vm.createContext({});
for (const name of ['typescript-5.9.3.js', 'formatter-vendors.js', 'tool-code-engine.js']) {
  vm.runInContext(fs.readFileSync('assets/javascript/' + name, 'utf8'), context);
}
const request = JSON.parse(fs.readFileSync(0, 'utf8'));
console.log(JSON.stringify(context.devutilsCodeOperation(request.source, request.operation, request.indentation || '2 spaces')));
