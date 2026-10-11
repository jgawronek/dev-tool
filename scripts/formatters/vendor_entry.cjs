// Bundled offline by build_vendor.cjs; no Node runtime is required by the app.
const beautify = require('js-beautify');
const csso = require('csso');
const minifyHtml = require('html-minifier').minify;
exports.process = function(source, operation, indentation) {
  const options = {
    indent_size: indentation === '4 spaces' ? 4 : 2,
    indent_with_tabs: indentation === 'Tabs',
    end_with_newline: false,
    preserve_newlines: true,
    max_preserve_newlines: 2,
  };
  switch (operation) {
    case 'CSS Beautify': return beautify.css(source, options);
    case 'CSS Minify': return csso.minify(source, {restructure: false}).css;
    case 'HTML Beautify': return beautify.html(source, {
      ...options,
      content_unformatted: ['pre', 'textarea', 'script', 'style'],
      indent_inner_html: true,
    });
    case 'HTML Minify': return minifyHtml(source, {
      collapseWhitespace: true,
      conservativeCollapse: false,
      removeComments: true,
      minifyCSS: false,
      minifyJS: false,
      removeAttributeQuotes: false,
      removeOptionalTags: false,
    });
    default: throw new Error('Unknown formatter operation: ' + operation);
  }
};
