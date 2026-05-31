// PHP -> JavaScript converter.
//
// This is a Dart port of Danack/PHP-to-Javascript
// (https://github.com/Danack/PHP-to-Javascript), which converts PHP into
// JavaScript using a token-stream state machine with scope tracking rather
// than a full AST. PHP's `token_get_all()` is reimplemented here as a Dart
// lexer; the ConverterStateMachine, scope tree and state classes mirror the
// original design.
//
// Like the original it is a best-effort transpiler: constructs that have no
// clean JavaScript equivalent (associative arrays, references, magic methods,
// etc.) are approximated. Output should be reviewed.

// ---------------------------------------------------------------------------
// Declaration flags
// ---------------------------------------------------------------------------
const int _flagStatic = 0x1;
const int _flagPrivate = 0x2;
const int _flagPublic = 0x4;
const int _flagClass = 0x8;
const int _flagNew = 0x10;

const String _constructorParamsPosition = '/*Constructor parameters here*/';
const String _endOfClassMarker = '/*END OF CLASS IS HERE*/';
const String _publicFunctionMarker = 'PUBLIC METHOD HERE';
const String _arrayElementStartMagic = '/*ARRAY_ELEMENT_START_MAGIC*/';

String _cVar(String value) => value.replaceAll(r'$', '');

String _convertPhpValueToJsValue(String value) {
  final lower = value.toLowerCase();
  if (lower == 'false') return 'false';
  if (lower == 'true') return 'true';
  if (lower == 'null') return 'null';
  if (value == 'Exception') return 'Error';
  return value;
}

String _convertMultiLineString(String string) {
  return string.replaceAll(RegExp(r'\r\n|\n|\r'), '\\\n');
}

String _unencapseString(String string) {
  var result = string;
  if (result.isNotEmpty && (result[0] == '"' || result[0] == "'")) {
    result = result.substring(1);
  }
  if (result.isNotEmpty &&
      (result[result.length - 1] == '"' || result[result.length - 1] == "'")) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------
class PhpToJsConverter {
  PhpToJsConverter._();

  static String convert(String phpCode) {
    final machine = _ConverterStateMachine();
    final stream = _TokenStream(phpTokenize(phpCode));
    _processTokenStream(stream, machine);
    var output = machine.finalize();
    output = output.replaceAll('STR_PAD_LEFT', "'STR_PAD_LEFT'");
    output = output.replaceAll('/*value*/', '+');
    return output.trimRight();
  }
}

void _processTokenStream(_TokenStream stream, _ConverterStateMachine machine) {
  machine.currentTokenStream = stream;
  while (stream.hasMoreTokens()) {
    final token = stream.next();
    final name = token.name;
    var value = token.value;

    var parsedToken = machine.parseToken(name, value);
    if (name == 'T_CONSTANT_ENCAPSED_STRING') {
      value = _convertMultiLineString(value);
    }
    if (name == 'T_ENCAPSED_AND_WHITESPACE') {
      parsedToken = _convertMultiLineString(parsedToken);
    }

    machine.accountForOpenBrackets(name);
    machine.accountForQuotes(name);
    machine.scopePreStateMagic(name, value);

    var count = 0;
    bool reprocess;
    do {
      reprocess = machine.processToken(name, value, parsedToken);
      if (count > 5) {
        // Safety valve identical to the original implementation.
        break;
      }
      count++;
    } while (reprocess);

    machine.accountForCloseBrackets(name);
    machine.scopePostStateMagic(name, value);

    if (name == 'T_VARIABLE') {
      if (machine.insertToken != null) {
        machine.addJS(machine.insertToken!);
        machine.insertToken = null;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Token stream
// ---------------------------------------------------------------------------
class PhpToken {
  PhpToken(this.name, this.value);
  final String name;
  final String value;
}

class _TokenStream {
  _TokenStream(this._tokens);
  final List<PhpToken> _tokens;
  int _current = 0;

  bool hasMoreTokens() => _current < _tokens.length;

  PhpToken next() => _tokens[_current++];

  void insertToken(String name, [String value = '']) {
    _tokens.insert(_current, PhpToken(name, value));
  }

  PhpToken? getPreviousNonWhitespaceToken() {
    var index = _current - 2; // -1 = current token, -2 = the previous one
    while (index >= 0) {
      final token = _tokens[index];
      if (token.name != 'T_COMMENT' && token.name != 'T_WHITESPACE') {
        return token;
      }
      index -= 1;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Variables & scopes
// ---------------------------------------------------------------------------
class _Variable {
  _Variable(this.name, this.flags);
  final String name;
  final int flags;
  bool get isPrivate => (flags & _flagPrivate) != 0;
  bool get isStatic => (flags & _flagStatic) != 0;
}

abstract class _CodeScope {
  _CodeScope(this.name, this.parentScope);

  String name;
  _CodeScope? parentScope;
  int bracketCount = 0;
  final List<Object> jsElements = [];
  final Map<String, _Variable> scopedVariables = {};
  final Map<String, String> defaultValues = {};

  String getType();
  String? getScopedVariableForScope(String variableName, int variableFlags);

  void addChild(_CodeScope scope) => jsElements.add(scope);
  void addJS(String js) => jsElements.add(js);

  String getJS() {
    final buffer = StringBuffer();
    for (final element in jsElements) {
      if (element is _CodeScope) {
        buffer.write(element.getJS());
      } else if (element is String) {
        buffer.write(element);
      }
    }
    return buffer.toString();
  }

  String getInPlaceJS() => getJS();
  String getDelayedJS(String parentScopeName) => '';
  String getEndOfScopeJS() => '';

  void pushBracket() => bracketCount += 1;

  bool popBracket() {
    bracketCount -= 1;
    return bracketCount <= 0;
  }

  void pushParens() {}
  bool popParens() => false;

  bool startOfFunction() => false;

  bool addScopedVariable(String variableName, int variableFlag) {
    if ((variableFlag & _flagClass) != 0) {
      if ((variableFlag & _flagPrivate) == 0) {
        return false;
      }
    }
    final cVar = _cVar(variableName);
    if (!scopedVariables.containsKey(cVar)) {
      scopedVariables[cVar] = _Variable(cVar, variableFlag);
      return true;
    }
    return false;
  }

  // Returns either the JS for the variable, or null if unknown in this scope.
  String? getScopedVariable(
    String variableName,
    int variableFlags,
    bool originalScope,
  ) {
    var result = getScopedVariableForScope(variableName, variableFlags);
    if (result == null && parentScope != null) {
      result = parentScope!.getScopedVariable(variableName, variableFlags, false);
    }
    if (originalScope && result == null) {
      if ((variableFlags & _flagClass) == 0) {
        addScopedVariable(variableName, variableFlags);
        result = 'var $variableName';
      } else {
        result = variableName;
      }
    }
    return result;
  }

  _Variable? getVariableFromScope(String variableName) {
    final result = scopedVariables[variableName];
    if (result != null) return result;
    return parentScope?.getVariableFromScope(variableName);
  }

  _CodeScope? findAncestorScopeByType(String type) {
    if (parentScope == null) return null;
    if (parentScope!.getType() == type) return parentScope;
    return parentScope!.findAncestorScopeByType(type);
  }

  Map<String, String> getVariablesWithDefaultParameters() => defaultValues;

  void preStateMagic(String name, String value) {}
  void postStateMagic(String name, String value) {}

  // ClassScope-only hooks (no-ops elsewhere, matching the original's loose OO).
  void addStaticVariable(String variableName) {}
  void addPublicVariable(String variableName) {}
  void addToVariableValue(String value) {}
  void addParent(String value) {}
  void markMethodsStart() {}

  bool previousTokensMatch(List<String> tokens) {
    final reversed = tokens.reversed.toList();
    var position = jsElements.length - 1;
    for (final token in reversed) {
      if (position < 0) return false;
      final element = jsElements[position];
      if (element is! String || element != token) return false;
      position--;
    }
    return true;
  }

  void deleteTokens(int count) {
    for (var i = 0; i < count && jsElements.isNotEmpty; i++) {
      jsElements.removeLast();
    }
  }
}

class _GlobalScope extends _CodeScope {
  _GlobalScope(super.name, super.parentScope);

  @override
  String getType() => 'CODE_SCOPE_GLOBAL';

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) {
    if ((variableFlags & _flagClass) != 0) return null;
    final cVar = _cVar(variableName);
    if (scopedVariables.containsKey(cVar)) return variableName;
    return null;
  }
}

class _FunctionScope extends _CodeScope {
  _FunctionScope(super.name, super.parentScope);

  @override
  String getType() => 'CODE_SCOPE_FUNCTION';

  @override
  bool startOfFunction() => bracketCount == 1;

  String getScopedName() {
    final containingClass = findAncestorScopeByType('CODE_SCOPE_CLASS');
    return containingClass == null ? name : 'this.$name';
  }

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) {
    final cVar = _cVar(variableName);
    final variable = scopedVariables[cVar];
    if (variable != null) {
      if (variable.isStatic) return '${getScopedName()}.$variableName';
      if ((variableFlags & _flagClass) != 0) {
        if (variableName.contains(r'$')) return 'this[$variableName]';
        return 'this.$variableName';
      }
      return variableName;
    }
    return null;
  }
}

class _FunctionParameterScope extends _CodeScope {
  _FunctionParameterScope(super.name, super.parentScope, this.variableFlag);

  int variableFlag;
  bool beforeVariable = true;

  @override
  String getType() => 'CODE_SCOPE_FUNCTION_PARAMETERS';

  void setBeforeVariable(bool value) => beforeVariable = value;

  @override
  bool addScopedVariable(String variableName, int variableFlag) {
    final result = super.addScopedVariable(variableName, variableFlag);
    setBeforeVariable(false);
    return result;
  }

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) {
    final cVar = _cVar(variableName);
    final variable = scopedVariables[cVar];
    if (variable != null) {
      if (variable.isStatic) return '$name.$variableName';
      if ((variableFlags & _flagClass) != 0) return 'this.$variableName';
      return variableName;
    }
    return null;
  }

  void addToJsForPreviousVariable(String value) {
    if (beforeVariable) return; // it's a type hint, not a default value
    if (scopedVariables.isEmpty) return;
    final variableName = scopedVariables.keys.last;
    defaultValues[variableName] =
        (defaultValues[variableName] ?? '') + _convertPhpValueToJsValue(value);
  }

  @override
  String getInPlaceJS() {
    if (name == '__construct') return '';
    if ((variableFlag & _flagPrivate) == 0) {
      var jsRaw = getJS();
      if ((variableFlag & _flagStatic) != 0) {
        return '';
      }
      jsRaw = jsRaw.replaceAll(_publicFunctionMarker, 'this.');
      jsRaw = '${jsRaw.trim()};\n\n';
      return jsRaw;
    }
    return getJS();
  }

  @override
  String getDelayedJS(String parentScopeName) {
    if (name == '__construct') return '';
    if ((variableFlag & _flagPrivate) == 0) {
      final jsRaw = getJS();
      if ((variableFlag & _flagStatic) != 0) {
        return jsRaw.replaceAll(_publicFunctionMarker, '$parentScopeName.');
      }
    }
    return '';
  }
}

class _CatchScope extends _CodeScope {
  _CatchScope(super.name, super.parentScope);

  final List<String> exceptionNames = [];

  @override
  String getType() => 'CODE_SCOPE_CATCH';

  void addExceptionName(String value) => exceptionNames.add(value);

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) {
    final cVar = _cVar(variableName);
    if (scopedVariables.containsKey(cVar)) {
      if ((variableFlags & _flagStatic) != 0) return '$name.$variableName';
      if ((variableFlags & _flagClass) != 0) {
        if (variableName.contains(r'$')) return 'this[$variableName]';
        return 'this.$variableName';
      }
      return variableName;
    }
    return null;
  }

  @override
  String getJS() {
    var jsRaw = super.getJS();
    for (final exceptionName in exceptionNames) {
      jsRaw = jsRaw.replaceAll(
        '$exceptionName.getMessage()',
        '$exceptionName.message',
      );
    }
    return jsRaw;
  }
}

class _ArrayScope extends _CodeScope {
  _ArrayScope(super.name, super.parentScope, this.variableFlag);

  int variableFlag;
  bool startedBySquareBracket = false;
  int squareBracketCount = 0;
  int parensCount = 0;
  int keyCount = 0;
  bool arrayElementStarted = false;
  bool doubleArrayUsed = false;
  String? variableName;

  @override
  String getType() => 'CODE_SCOPE_ARRAY';

  void setVariableName(String value) => variableName = value;

  @override
  void pushParens() => parensCount += 1;

  @override
  bool popParens() {
    parensCount -= 1;
    return parensCount <= 0;
  }

  void incrementSquareBracketCount() => squareBracketCount++;
  void decrementSquareBracketCount() => squareBracketCount--;
  int getSquareBracketCount() => squareBracketCount;

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) =>
      null;

  @override
  String getJS() {
    var js = super.getJS();
    final firstOpen = js.indexOf('(');
    if (firstOpen != -1) {
      js = '${js.substring(0, firstOpen)}{${js.substring(firstOpen + 1)}}';
    }
    final lastClose = js.lastIndexOf(')');
    if (lastClose != -1) {
      js = '${js.substring(0, lastClose)}}${js.substring(lastClose + 1)}';
    }
    final parent = parentScope;
    if (parent is _ClassScope && variableName != null) {
      parent.setVariableString(variableName!, js);
      return '/* $variableName */';
    }
    return js;
  }

  void fixupArrayIndex() {
    var replace = '';
    if (!doubleArrayUsed) {
      replace = '$keyCount : ';
      keyCount++;
    }
    for (var x = jsElements.length - 1; x >= 0; x--) {
      if (jsElements[x] == _arrayElementStartMagic) {
        jsElements[x] = replace;
        break;
      }
    }
    doubleArrayUsed = false;
    arrayElementStarted = false;
  }

  @override
  void preStateMagic(String name, String value) {
    if (!arrayElementStarted) {
      if (name == 'T_LNUMBER' ||
          name == 'T_VARIABLE' ||
          name == 'T_CONSTANT_ENCAPSED_STRING' ||
          name == 'T_ARRAY' ||
          name == '[') {
        addJS(_arrayElementStartMagic);
        arrayElementStarted = true;
      }
    }
    if (name == 'T_DOUBLE_ARROW') doubleArrayUsed = true;
    if (name == ',' || name == ')') fixupArrayIndex();
  }
}

class _ClassScope extends _CodeScope {
  _ClassScope(super.name, super.parentScope);

  final Map<String, String?> publicVariables = {};
  final Map<String, String?> staticVariables = {};
  final List<String> parentClasses = [];
  int methodsStartIndex = -1;
  String? currentVariableName;
  String? _currentVariableTarget; // 'static' or 'public'

  @override
  String getType() => 'CODE_SCOPE_CLASS';

  @override
  void addParent(String value) => parentClasses.add(value);

  @override
  void markMethodsStart() {
    if (methodsStartIndex < 0) methodsStartIndex = jsElements.length;
  }

  @override
  void addStaticVariable(String variableName) {
    staticVariables[variableName] = null;
    currentVariableName = variableName;
    _currentVariableTarget = 'static';
  }

  @override
  void addPublicVariable(String variableName) {
    publicVariables[variableName] = null;
    currentVariableName = variableName;
    _currentVariableTarget = 'public';
  }

  void setVariableString(String variableName, String string) {
    if (staticVariables.containsKey(variableName)) {
      staticVariables[variableName] = string;
      return;
    }
    if (publicVariables.containsKey(variableName)) {
      publicVariables[variableName] = string;
    }
  }

  @override
  void addToVariableValue(String value) {
    if (_currentVariableTarget == null || currentVariableName == null) return;
    final map = _currentVariableTarget == 'static'
        ? staticVariables
        : publicVariables;
    map[currentVariableName!] = (map[currentVariableName!] ?? '') + value;
  }

  @override
  String? getScopedVariableForScope(String variableName, int variableFlags) {
    final cVar = _cVar(variableName);
    if (scopedVariables.containsKey(cVar)) {
      if ((variableFlags & _flagClass) != 0) {
        if ((variableFlags & _flagPrivate) != 0) return variableName;
        if ((variableFlags & _flagStatic) != 0) return variableName;
        if ((variableFlags & _flagPublic) != 0) return 'this.$variableName';
      }
    }
    if ((variableFlags & _flagClass) != 0) {
      if ((variableFlags & _flagStatic) != 0) return variableName;
      return 'this.$variableName';
    }
    return null;
  }

  String _getClassInheritanceJS() {
    if (parentClasses.isEmpty) return '';
    final buffer = StringBuffer('\n\n');
    for (final parentClass in parentClasses) {
      final childClass = name;
      buffer.writeln('// inherit $parentClass');
      buffer.writeln('$childClass.prototype = new $parentClass();');
      buffer.writeln('$childClass.prototype.constructor = $childClass;');
      buffer.writeln('Object.assign($childClass, $parentClass);');
    }
    buffer.write('\n');
    return buffer.toString();
  }

  String _getClassVariableInitJS() {
    final buffer = StringBuffer();
    staticVariables.forEach((name, value) {
      buffer.writeln('${this.name}.$name = ${value ?? 'null'};');
    });
    return buffer.toString();
  }

  @override
  String getEndOfScopeJS() {
    return '\n${_getClassInheritanceJS()}\n${_getClassVariableInitJS()}';
  }

  String _getJSForClassInPlace() {
    final parts = <String>[];
    for (final element in jsElements) {
      if (element is _CodeScope) {
        parts.add(element.getInPlaceJS());
      } else if (element is String) {
        parts.add(element);
      }
    }
    final lastElement = parts.isNotEmpty ? parts.removeLast() : '';
    publicVariables.forEach((name, value) {
      parts.add('this.$name = ${value ?? 'null'};\n');
    });
    parts.add(_endOfClassMarker);
    parts.add(lastElement);
    return parts.join();
  }

  String getChildDelayedJS() {
    final buffer = StringBuffer();
    for (final element in jsElements) {
      if (element is _CodeScope) {
        buffer.write(element.getDelayedJS(name));
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  @override
  String getJS() {
    var js = _getJSForClassInPlace();
    js += '\n${getEndOfScopeJS()}\n${getChildDelayedJS()}';
    js = _replaceConstructorInJS(js);
    js = _manglePrivateFunctions(js);
    return js;
  }

  String _manglePrivateFunctions(String js) {
    var result = js;
    for (final element in jsElements) {
      if (element is _FunctionParameterScope) {
        if ((element.variableFlag & _flagPrivate) != 0) {
          result = result.replaceAll(
            'this.${element.name}(',
            '${element.name}(',
          );
        }
      }
    }
    return result;
  }

  String _replaceConstructorInJS(String js) {
    String? constructor;
    for (final element in jsElements) {
      if (element is _CodeScope && element.name == '__construct') {
        constructor = element.getJS();
        break;
      }
    }
    final parentConstructor = StringBuffer();
    for (final parentClass in parentClasses) {
      parentConstructor.writeln('$parentClass.call(this);');
    }
    var result = js;
    if (constructor != null) {
      final info = _trimConstructor(constructor);
      final body = parentConstructor.toString() + info.body;
      result = result.replaceAll(_constructorParamsPosition, info.parameters);
      result = result.replaceAll(_endOfClassMarker, body);
    } else {
      result = result.replaceAll(_constructorParamsPosition, '');
      result = result.replaceAll(_endOfClassMarker, parentConstructor.toString());
    }
    return result;
  }
}

class _ConstructorInfo {
  _ConstructorInfo(this.parameters, this.body);
  final String parameters;
  final String body;
}

_ConstructorInfo _trimConstructor(String constructor) {
  final firstBracket = constructor.indexOf('(');
  final closeBracket = firstBracket == -1
      ? -1
      : constructor.indexOf(')', firstBracket + 1);
  final firstBrace = constructor.indexOf('{');
  final lastBrace = constructor.lastIndexOf('}');
  if (firstBrace == -1 || lastBrace == -1) {
    return _ConstructorInfo('', '');
  }
  final parameters = (firstBracket != -1 && closeBracket != -1)
      ? constructor.substring(firstBracket + 1, closeBracket)
      : '';
  final body = constructor.substring(firstBrace + 1, lastBrace);
  return _ConstructorInfo(parameters, body);
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------
const Map<String, String> _convertMap = {
  'T_IS_EQUAL': '==',
  'T_IS_GREATER_OR_EQUAL': '>=',
  'T_IS_SMALLER_OR_EQUAL': '<=',
  'T_IS_IDENTICAL': '===',
  'T_IS_NOT_EQUAL': '!=',
  'T_IS_NOT_IDENTICAL': '!==',
  'T_BOOLEAN_AND': '&&',
  'T_BOOLEAN_OR': '||',
  'T_CONCAT_EQUAL': '+= ',
  'T_DIV_EQUAL': '/=',
  'T_INC': '++',
  'T_DEC': '--',
  'T_MINUS_EQUAL': '-=',
  'T_MOD_EQUAL': '%=',
  'T_MUL_EQUAL': '*=',
  'T_OBJECT_OPERATOR': '.',
  'T_OR_EQUAL': '|=',
  'T_PLUS_EQUAL': '+=',
  'T_SL': '<<',
  'T_SL_EQUAL': '<<=',
  'T_SR': '>>',
  'T_SR_EQUAL': '>>=',
  'T_XOR_EQUAL': '^=',
  'T_ELSE': 'else',
  '.': ' + "" + ',
  'T_IF': 'if',
  'T_RETURN': 'return',
  'T_AS': 'in',
  'T_WHILE': 'while',
  'T_LOGICAL_AND': '&&',
  'T_LOGICAL_OR': '||',
  'T_LOGICAL_XOR': '^',
  'T_EVAL': 'eval',
  'T_ELSEIF': 'else if',
  'T_BREAK': 'break',
  'T_INSTANCEOF': 'instanceof',
};

const Set<String> _keepSet = {
  '}', '{', ';', '(', '*', '/', '+', '-', '>', '<', '[', ']', '"', "'", ':',
  '%', '?', '!',
};

const Set<String> _keepValueSet = {
  'T_STRING',
  'T_COMMENT',
  'T_ML_COMMENT',
  'T_DOC_COMMENT',
  'T_LNUMBER',
  'T_ENCAPSED_AND_WHITESPACE',
  'T_WHITESPACE',
  'T_SWITCH',
  'T_CASE',
  'T_DEFAULT',
  'T_THROW',
  'T_FOR',
  'T_CONTINUE',
  'T_DNUMBER',
};

class _ConverterStateMachine {
  _ConverterStateMachine() {
    pushScope('CODE_SCOPE_GLOBAL', 'GLOBAL');
    _states['DEFAULT'] = _StateDefault(this);
    _states['ECHO'] = _StateEcho(this);
    _states['ARRAY'] = _StateArray(this);
    _states['CLASS'] = _StateClass(this);
    _states['FUNCTION'] = _StateFunction(this);
    _states['FOREACH'] = _StateForeach(this);
    _states['VARIABLE'] = _StateVariable(this);
    _states['VARIABLE_GLOBAL'] = _StateVariableGlobal(this);
    _states['VARIABLE_FUNCTION'] = _StateVariableFunction(this);
    _states['VARIABLE_CLASS'] = _StateVariableClass(this);
    _states['VARIABLE_FUNCTION_PARAMETER'] = _StateVariableParameter(this);
    _states['VARIABLE_ARRAY'] = _StateVariableArray(this);
    _states['VARIABLE_CATCH'] = _StateVariableCatch(this);
    _states['STATIC'] = _StateStatic(this);
    _states['STRING'] = _StateString(this);
    _states['T_PUBLIC'] = _StatePublic(this);
    _states['T_PRIVATE'] = _StatePrivate(this);
    _states['DEFINE'] = _StateDefine(this);
    _states['T_EXTENDS'] = _StateExtends(this);
    _states['T_NEW'] = _StateNew(this);
    _states['VARIABLE_DEFAULT'] = _StateVariableDefault(this);
    _states['EQUALS'] = _StateEquals(this);
    _states['CLOSE_PARENS'] = _StateCloseParens(this);
    _states['COMMA'] = _StateComma(this);
    _states['DOUBLE_ARROW'] = _StateDoubleArrow(this);
    _states['IMPLEMENTS_INTERFACE'] = _StateImplementsInterface(this);
    _states['INTERFACE'] = _StateInterface(this);
    _states['REQUIRE'] = _StateRequire(this);
    _states['ABSTRACT'] = _StateAbstract(this);
    _states['ABSTRACT_FUNCTION'] = _StateAbstractRemove(this);
    _states['END_OF_CLASS'] = _StateEndOfClass(this);
    _states['VARIABLE_VALUE'] = _StateVariableValue(this);
    _states['OBJECT_OPERATOR'] = _StateObjectOperator(this);
    _states['DOUBLE_COLON'] = _StateDoubleColon(this);
    _states['NAME_SPACE'] = _StateNamespace(this);
    _states['IMPORT_NAMESPACE'] = _StateImportNamespace(this);
    _states['T_USE'] = _StateUse(this);
    _states['T_UNSET'] = _StateUnset(this);
    _states['T_TRY'] = _StateTry(this);
    _states['T_CATCH'] = _StateCatch(this);
    _states['PUBLIC'] = _states['T_PUBLIC']!;
    _states['GLOBAL'] = _StateGlobal(this);
    _states['SKIP_TO_SEMICOLON'] = _StateSkipToSemicolon(this);
    _states['CAPTURING_DEFAULT_VALUE'] = _StateCapturingDefaultValue(this);
    _states['EMBEDDED_VARIABLE'] = _StateEmbeddedVariable(this);
    currentState = 'DEFAULT';
  }

  final Map<String, _State> _states = {};
  String currentState = 'DEFAULT';
  int variableFlags = 0;
  late _CodeScope rootScope;
  late _CodeScope currentScope;
  final List<_CodeScope> scopesStack = [];
  final Map<String, String> defines = {};
  String? quoteOpen;
  String? insertToken;
  final List<List<String>> pendingSymbols = [];
  _TokenStream? currentTokenStream;

  _State getState() => _states[currentState]!;

  void changeToState(String newState, [Map<String, Object?> params = const {}]) {
    final state = _states[newState];
    if (state == null) {
      throw StateError('Unknown state [$newState]');
    }
    currentState = newState;
    state.enterState(params);
  }

  bool processToken(String name, String value, String parsedToken) {
    return getState().processToken(name, value, parsedToken);
  }

  void clearVariableFlags() => variableFlags = 0;
  void addVariableFlags(int flag) => variableFlags |= flag;

  void addJS(String js) => currentScope.addJS(js);

  String getJS() => rootScope.getJS();
  String finalize() => getJS();

  bool addScopedVariable(String variableName, int variableFlags) =>
      currentScope.addScopedVariable(variableName, variableFlags);

  String? getVariableNameForScope(String variableName, int variableFlags) =>
      currentScope.getScopedVariable(variableName, variableFlags, true);

  _Variable? getVariableFromScope(String variableName, String scopeType) {
    final scope = currentScope.findAncestorScopeByType(scopeType);
    return scope?.getVariableFromScope(variableName);
  }

  _CodeScope? findScopeType(String type) {
    for (final scope in scopesStack) {
      if (scope.getType() == type) return scope;
    }
    if (currentScope.getType() == type) return currentScope;
    return null;
  }

  String getClassName() {
    final scope = findScopeType('CODE_SCOPE_CLASS') ?? currentScope;
    return scope.name;
  }

  bool previousTokensMatch(List<String> tokens) =>
      currentScope.previousTokensMatch(tokens);
  void deleteTokens(int count) => currentScope.deleteTokens(count);

  PhpToken? getPreviousNonWhitespaceToken() =>
      currentTokenStream?.getPreviousNonWhitespaceToken();

  void accountForOpenBrackets(String name) {
    if (name == '{') currentScope.pushBracket();
    if (name == '(') currentScope.pushParens();
  }

  void accountForQuotes(String name) {
    if (name == '"' || name == "'") {
      if (quoteOpen == name) {
        quoteOpen = null;
      } else {
        quoteOpen = name;
      }
    }
  }

  String encloseVariable(String variableName) {
    if (quoteOpen == null) return variableName;
    return '$quoteOpen + $variableName + $quoteOpen';
  }

  void accountForCloseBrackets(String name) {
    var scopeEnded = false;
    if (name == '}') {
      scopeEnded = currentScope.popBracket();
    } else if (name == ')') {
      scopeEnded = currentScope.popParens();
    }
    if (scopeEnded && currentScope is! _GlobalScope) {
      final popped = currentScope;
      popCurrentScope();
      if (popped is _FunctionScope) {
        popCurrentScope(); // also pop the function-parameters scope
      }
    }
  }

  String parseToken(String name, String value) {
    var result = _getPendingInsert(name);
    if (name == 'T_VARIABLE') {
      result += value;
    } else if (_convertMap.containsKey(name)) {
      final mapped = _convertMap[name]!;
      result += mapped.isEmpty ? name : mapped;
    } else if (_keepSet.contains(name)) {
      result += name;
    } else if (name == 'T_STRING' && defines.containsKey(value)) {
      result += defines[value]!;
    } else if (_keepValueSet.contains(name)) {
      result += value;
    }
    if (result == 'NULL') result = 'null';
    return result;
  }

  String _getPendingInsert(String symbolToCheck) {
    for (var i = 0; i < pendingSymbols.length; i++) {
      if (pendingSymbols[i][0] == symbolToCheck) {
        final insert = pendingSymbols[i][1];
        pendingSymbols.removeAt(i);
        return insert;
      }
    }
    return '';
  }

  void addSymbolAfterNextToken(String symbol) => insertToken = symbol;
  void setPendingSymbol(String symbol, String insert) =>
      pendingSymbols.add([symbol, insert]);

  void pushScope(String type, String name, [int variableFlag = 0]) {
    final hasCurrent = scopesStack.isNotEmpty || _rootInitialised;
    if (hasCurrent) {
      scopesStack.add(currentScope);
    }
    final _CodeScope newScope;
    switch (type) {
      case 'CODE_SCOPE_GLOBAL':
        newScope = _GlobalScope(name, _rootInitialised ? currentScope : null);
        break;
      case 'CODE_SCOPE_CLASS':
        newScope = _ClassScope(name, currentScope);
        break;
      case 'CODE_SCOPE_FUNCTION_PARAMETERS':
        newScope = _FunctionParameterScope(name, currentScope, variableFlag);
        break;
      case 'CODE_SCOPE_FUNCTION':
        newScope = _FunctionScope(name, currentScope);
        break;
      case 'CODE_SCOPE_ARRAY':
        newScope = _ArrayScope(name, currentScope, variableFlag);
        break;
      case 'CODE_SCOPE_CATCH':
        newScope = _CatchScope(name, currentScope);
        break;
      default:
        throw StateError('Unknown scope type [$type]');
    }
    if (!_rootInitialised) {
      rootScope = newScope;
      _rootInitialised = true;
    } else {
      currentScope.addChild(newScope);
    }
    currentScope = newScope;
  }

  bool _rootInitialised = false;

  void popCurrentScope() {
    final previousScope = currentScope;
    currentScope = scopesStack.isNotEmpty ? scopesStack.removeLast() : rootScope;
    if (previousScope is _ClassScope) {
      changeToState('END_OF_CLASS', {'previousScope': previousScope});
    }
  }

  void startArrayScope(String scopeName, bool startedBySquareBracket) {
    _ClassScope? classScope;
    if (currentScope is _ClassScope) classScope = currentScope as _ClassScope;
    pushScope('CODE_SCOPE_ARRAY', scopeName);
    changeToState('DEFAULT');
    if (classScope != null) {
      (currentScope as _ArrayScope)
          .setVariableName(classScope.currentVariableName ?? '');
    }
    final arrayScope = currentScope as _ArrayScope;
    if (startedBySquareBracket) arrayScope.incrementSquareBracketCount();
    arrayScope.startedBySquareBracket = startedBySquareBracket;
  }

  void scopePreStateMagic(String name, String value) =>
      currentScope.preStateMagic(name, value);
  void scopePostStateMagic(String name, String value) =>
      currentScope.postStateMagic(name, value);

  void addDefine(String name, String value) => defines[name] = value;
  bool isDefined(String name) => defines.containsKey(name);
  String? getDefine(String name) => defines[name];

  void addDefaultsForVariables() {
    final scope = findScopeType('CODE_SCOPE_FUNCTION_PARAMETERS');
    if (scope == null) return;
    final defaults = scope.getVariablesWithDefaultParameters();
    defaults.forEach((variable, defaultValue) {
      addJS(
        '\n\t\tif(typeof $variable === "undefined"){\n'
        '\t\t\t$variable = $defaultValue;\n'
        '\t\t}\n',
      );
    });
  }
}

// ---------------------------------------------------------------------------
// State classes
// ---------------------------------------------------------------------------
abstract class _State {
  _State(this.machine);
  final _ConverterStateMachine machine;
  void enterState(Map<String, Object?> params) {}
  bool processToken(String name, String value, String parsedToken);
}

class _StateDefault extends _State {
  _StateDefault(super.machine);

  static const Map<String, String> _tokenStateChangeList = {
    'T_ECHO': 'ECHO',
    'T_ARRAY': 'ARRAY',
    'T_CLASS': 'CLASS',
    'T_TRAIT': 'CLASS',
    'T_FUNCTION': 'FUNCTION',
    'T_FOREACH': 'FOREACH',
    'T_PUBLIC': 'PUBLIC',
    'T_PROTECTED': 'PUBLIC',
    'T_VARIABLE': 'VARIABLE',
    'T_STATIC': 'STATIC',
    'T_STRING': 'STRING',
    'T_VAR': 'T_PUBLIC',
    'T_PRIVATE': 'T_PRIVATE',
    'T_EXTENDS': 'T_EXTENDS',
    'T_USE': 'T_USE',
    'T_NEW': 'T_NEW',
    'T_CONSTANT_ENCAPSED_STRING': 'VARIABLE_DEFAULT',
    '=': 'EQUALS',
    ')': 'CLOSE_PARENS',
    'T_REQUIRE_ONCE': 'REQUIRE',
    'T_REQUIRE': 'REQUIRE',
    'T_INCLUDE': 'REQUIRE',
    'T_INCLUDE_ONCE': 'REQUIRE',
    'T_IMPLEMENTS': 'IMPLEMENTS_INTERFACE',
    'T_ABSTRACT': 'ABSTRACT',
    'T_INTERFACE': 'INTERFACE',
    'T_OBJECT_OPERATOR': 'OBJECT_OPERATOR',
    ',': 'COMMA',
    'T_DOUBLE_ARROW': 'DOUBLE_ARROW',
    'T_DOUBLE_COLON': 'DOUBLE_COLON',
    'T_NAMESPACE': 'NAME_SPACE',
    'T_UNSET': 'T_UNSET',
    'T_TRY': 'T_TRY',
    'T_CATCH': 'T_CATCH',
    'T_GLOBAL': 'GLOBAL',
    'T_DOLLAR_OPEN_CURLY_BRACES': 'EMBEDDED_VARIABLE',
  };

  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_STRING' && value == 'define') {
      machine.changeToState('DEFINE');
      return true;
    }

    if (name == '[') {
      final previous = machine.getPreviousNonWhitespaceToken();
      final prevName = previous?.name;
      if (prevName == '=' ||
          prevName == 'T_DOUBLE_ARROW' ||
          prevName == ',' ||
          prevName == '(' ||
          prevName == '[') {
        machine.startArrayScope('', true);
        machine.currentTokenStream?.insertToken('(');
        return false;
      } else if (machine.currentScope is _ArrayScope) {
        (machine.currentScope as _ArrayScope).incrementSquareBracketCount();
      }
    }

    if (name == ']') {
      if (machine.currentScope is _ArrayScope) {
        final scope = machine.currentScope as _ArrayScope;
        scope.decrementSquareBracketCount();
        if (scope.getSquareBracketCount() <= 0 && scope.startedBySquareBracket) {
          machine.currentTokenStream?.insertToken(')');
          return false;
        }
        scope.addJS(']');
        return false;
      }
    }

    if (_tokenStateChangeList.containsKey(name)) {
      machine.changeToState(_tokenStateChangeList[name]!);
      return true;
    }

    if (name == 'T_LNUMBER' && machine.currentScope is _FunctionParameterScope) {
      machine.changeToState('VARIABLE_DEFAULT');
      return true;
    }

    machine.addJS(parsedToken);

    if (name == '{' && machine.currentScope.startOfFunction()) {
      machine.addDefaultsForVariables();
    }
    return false;
  }
}

class _StateEcho extends _State {
  _StateEcho(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS('console.log(');
    machine.addJS(parsedToken);
    machine.setPendingSymbol(';', ')');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariable extends _State {
  _StateVariable(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final scope = machine.currentScope;
    if (scope is _GlobalScope) {
      machine.changeToState('VARIABLE_GLOBAL');
    } else if (scope is _FunctionScope) {
      machine.changeToState('VARIABLE_FUNCTION');
    } else if (scope is _FunctionParameterScope) {
      machine.changeToState('VARIABLE_FUNCTION_PARAMETER');
    } else if (scope is _ClassScope) {
      machine.changeToState('VARIABLE_CLASS');
    } else if (scope is _ArrayScope) {
      machine.changeToState('VARIABLE_ARRAY');
    } else if (scope is _CatchScope) {
      machine.changeToState('VARIABLE_CATCH');
    } else {
      machine.addJS(_cVar(value));
      machine.changeToState('DEFAULT');
      return false;
    }
    return true;
  }
}

class _StateVariableGlobal extends _State {
  _StateVariableGlobal(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final variableName = _cVar(value);
    final wasAdded =
        machine.addScopedVariable(variableName, machine.variableFlags);
    if (wasAdded) machine.addJS('var ');
    machine.addJS(machine.encloseVariable(variableName));
    machine.clearVariableFlags();
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariableFunction extends _State {
  _StateVariableFunction(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (value == r'$this') {
      machine.addJS('this');
      machine.addVariableFlags(_flagClass);
      return false;
    }
    final variableName = _cVar(value);
    final isClassVariable = (machine.variableFlags & _flagClass) != 0;
    if ((machine.variableFlags & _flagStatic) != 0 && !isClassVariable) {
      machine.addScopedVariable(variableName, machine.variableFlags);
      final scopedName =
          machine.getVariableNameForScope(variableName, machine.variableFlags);
      machine.addJS("if (typeof $scopedName == 'undefined')\n ");
    }
    if (isClassVariable && (name == ')' || name == ',' || name == ';')) {
      machine.addJS(name);
    } else if (name == 'T_OBJECT_OPERATOR') {
      machine.addJS('.');
    } else if (name == 'T_STRING' || name == 'T_VARIABLE') {
      final scopedVariableName =
          machine.getVariableNameForScope(variableName, machine.variableFlags) ??
              variableName;
      machine.addJS(machine.encloseVariable(scopedVariableName));
      machine.variableFlags = 0;
    } else {
      // Unexpected token: emit the variable to stay resilient.
      final scopedVariableName =
          machine.getVariableNameForScope(variableName, machine.variableFlags) ??
              variableName;
      machine.addJS(machine.encloseVariable(scopedVariableName));
    }
    machine.clearVariableFlags();
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariableClass extends _State {
  _StateVariableClass(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final variableName = _cVar(value);
    if (value == r'$this') machine.addJS('this');
    machine.addScopedVariable(variableName, machine.variableFlags);
    if ((machine.variableFlags & _flagStatic) != 0) {
      machine.currentScope.addStaticVariable(variableName);
      machine.changeToState('VARIABLE_VALUE');
    } else if ((machine.variableFlags & _flagPublic) != 0) {
      machine.currentScope.addPublicVariable(variableName);
      machine.changeToState('VARIABLE_VALUE');
    } else {
      machine.addJS('var ');
      machine.addJS(variableName);
      machine.clearVariableFlags();
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateVariableParameter extends _State {
  _StateVariableParameter(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final variableName = _cVar(value);
    machine.addScopedVariable(variableName, machine.variableFlags);
    machine.addJS(variableName);
    machine.changeToState('CAPTURING_DEFAULT_VALUE');
    return false;
  }
}

class _StateVariableArray extends _State {
  _StateVariableArray(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS(_cVar(value));
    machine.clearVariableFlags();
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariableCatch extends _State {
  _StateVariableCatch(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final variableName = _cVar(value);
    machine.addScopedVariable(variableName, machine.variableFlags);
    (machine.currentScope as _CatchScope).addExceptionName(variableName);
    machine.addJS(variableName);
    machine.clearVariableFlags();
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariableDefault extends _State {
  _StateVariableDefault(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (machine.currentScope is _FunctionParameterScope) {
      (machine.currentScope as _FunctionParameterScope)
          .addToJsForPreviousVariable(value);
    } else {
      machine.addJS(value);
    }
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateVariableValue extends _State {
  _StateVariableValue(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_WHITESPACE' ||
        name == '=' ||
        name == 'T_CONSTANT_ENCAPSED_STRING' ||
        name == 'T_LNUMBER' ||
        name == 'T_COMMENT' ||
        name == 'T_STRING') {
      machine.currentScope.addToVariableValue(_convertPhpValueToJsValue(value));
      return false;
    }
    if (name == ';') {
      machine.clearVariableFlags();
      machine.changeToState('DEFAULT');
      return false;
    }
    if (name == 'T_ARRAY') {
      machine.changeToState('ARRAY');
      return true;
    }
    if (name == '[') {
      machine.startArrayScope('', true);
      machine.currentTokenStream?.insertToken('(');
      return false;
    }
    // Resilient fallback.
    machine.changeToState('DEFAULT');
    return true;
  }
}

class _StateEquals extends _State {
  _StateEquals(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS(name);
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateComma extends _State {
  _StateComma(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS(',');
    if (machine.currentScope is _FunctionParameterScope) {
      (machine.currentScope as _FunctionParameterScope).setBeforeVariable(true);
    }
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateDoubleArrow extends _State {
  _StateDoubleArrow(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS(':');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateFunction extends _State {
  _StateFunction(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == '(') {
      machine.pushScope(
        'CODE_SCOPE_FUNCTION_PARAMETERS',
        '',
        machine.variableFlags,
      );
      machine.addJS('function ');
      machine.clearVariableFlags();
      machine.changeToState('DEFAULT');
      return true;
    }
    if (name == 'T_STRING') {
      final previousScope = machine.currentScope;
      machine.pushScope(
        'CODE_SCOPE_FUNCTION_PARAMETERS',
        value,
        machine.variableFlags,
      );
      if (previousScope is _ClassScope) {
        previousScope.markMethodsStart();
        if ((machine.variableFlags & _flagPrivate) != 0) {
          machine.addJS('function $value ');
        } else {
          machine.addJS('$_publicFunctionMarker$value = function ');
        }
      } else {
        machine.addJS('function $value ');
      }
      machine.clearVariableFlags();
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateClass extends _State {
  _StateClass(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_STRING') {
      machine.pushScope('CODE_SCOPE_CLASS', value);
      machine.addJS('function $value($_constructorParamsPosition)');
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateForeach extends _State {
  _StateForeach(super.machine);

  final List<String> _arrayElements = [];
  final List<String> _keyOrValueElements = [];
  final List<String> _valueElements = [];
  String _subState = 'OBJECT';

  @override
  void enterState(Map<String, Object?> params) {
    _arrayElements.clear();
    _keyOrValueElements.clear();
    _valueElements.clear();
    _subState = 'OBJECT';
  }

  @override
  bool processToken(String name, String value, String parsedToken) {
    String? jsToAdd;
    if (name == 'T_VARIABLE') {
      jsToAdd = _cVar(value);
    } else if (name == 'T_OBJECT_OPERATOR' || name == 'T_DOUBLE_COLON') {
      jsToAdd = '.';
    } else if (name == 'T_STRING') {
      jsToAdd = value.toLowerCase() == 'self' ? machine.getClassName() : value;
    } else if (name == 'T_WHITESPACE') {
      jsToAdd = value;
    }

    if (name == 'T_AS') _subState = 'KEY_OR_VALUE';
    if (name == 'T_DOUBLE_ARROW') _subState = 'VALUE';

    if (jsToAdd != null) {
      switch (_subState) {
        case 'OBJECT':
          _arrayElements.add(jsToAdd);
          break;
        case 'KEY_OR_VALUE':
          _keyOrValueElements.add(jsToAdd);
          break;
        case 'VALUE':
          _valueElements.add(jsToAdd);
          break;
      }
    }

    if (name == '{') {
      _finalise();
      machine.changeToState('DEFAULT');
    }
    return false;
  }

  void _finalise() {
    final array = _arrayElements.join().trim();
    if (_valueElements.isEmpty) {
      final value = _keyOrValueElements.join().trim();
      machine.addJS(
        'for (var ${value}Key in $array) {\n'
        '                 var $value = $array[${value}Key];',
      );
      machine.currentScope.addScopedVariable(value, 0);
    } else {
      final key = _keyOrValueElements.join().trim();
      final value = _valueElements.join().trim();
      machine.addJS(
        'for (var $key in $array) {\n'
        '       var $value = $array[$key];',
      );
      machine.currentScope.addScopedVariable(key, 0);
      machine.currentScope.addScopedVariable(value, 0);
    }
  }
}

class _StateObjectOperator extends _State {
  _StateObjectOperator(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_VARIABLE') {
      if (value.contains(r'$')) {
        machine.addJS('[');
        machine.addSymbolAfterNextToken(']');
      } else {
        machine.addJS('.');
      }
      machine.changeToState('VARIABLE');
      return true;
    }
    if (name == 'T_STRING') {
      machine.addJS('.');
      machine.changeToState('DEFAULT');
      return true;
    }
    return false;
  }
}

class _StateDoubleColon extends _State {
  _StateDoubleColon(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addVariableFlags(_flagClass);
    machine.addVariableFlags(_flagStatic);
    machine.addJS('.');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateNew extends _State {
  _StateNew(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS('new');
    machine.addVariableFlags(_flagNew);
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateStatic extends _State {
  _StateStatic(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if ((machine.variableFlags & _flagNew) != 0) {
      machine.addJS('this.prototype.constructor');
    } else {
      machine.variableFlags |= _flagStatic;
    }
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StatePublic extends _State {
  _StatePublic(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.variableFlags |= _flagPublic;
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StatePrivate extends _State {
  _StatePrivate(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.variableFlags |= _flagPrivate;
    machine.variableFlags |= _flagClass;
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateArray extends _State {
  _StateArray(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (machine.currentScope is _FunctionParameterScope) {
      if ((machine.currentScope as _FunctionParameterScope).beforeVariable) {
        machine.addJS('/*$value*/');
        machine.changeToState('DEFAULT');
        return false;
      }
    }
    machine.startArrayScope(value, false);
    return false;
  }
}

class _StateCloseParens extends _State {
  _StateCloseParens(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (machine.currentScope is _FunctionParameterScope ||
        machine.currentScope is _CatchScope) {
      machine.pushScope('CODE_SCOPE_FUNCTION', machine.currentScope.name);
    }
    machine.addJS(')');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateExtends extends _State {
  _StateExtends(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_STRING') {
      machine.currentScope.addParent(value);
    }
    if (name == '{') {
      machine.changeToState('DEFAULT');
      return true;
    }
    return false;
  }
}

class _StateDefine extends _State {
  _StateDefine(super.machine);
  String? _defineName;
  bool _pastDefineToken = false;

  @override
  void enterState(Map<String, Object?> params) {
    _defineName = null;
    _pastDefineToken = false;
    machine.addJS('// ');
  }

  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS(parsedToken);
    if (name == 'T_CONSTANT_ENCAPSED_STRING') {
      if (_defineName == null) {
        _defineName = _unencapseString(value);
      } else {
        machine.addDefine(_defineName!, _unencapseString(value));
        machine.changeToState('DEFAULT');
      }
    } else if (name == 'T_LNUMBER') {
      machine.addDefine(_defineName ?? '', value);
      machine.changeToState('DEFAULT');
    } else if (name == 'T_DNUMBER') {
      machine.addDefine(_defineName ?? '', value);
      machine.changeToState('DEFAULT');
    } else if (name == 'T_STRING') {
      machine.addDefine(_defineName ?? '', _convertPhpValueToJsValue(value));
      if (_pastDefineToken) machine.changeToState('DEFAULT');
    }
    _pastDefineToken = true;
    return false;
  }
}

class _StateTry extends _State {
  _StateTry(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS('try');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateCatch extends _State {
  _StateCatch(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_CATCH') {
      machine.addJS('catch');
      machine.pushScope('CODE_SCOPE_CATCH', 'catch');
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateGlobal extends _State {
  _StateGlobal(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.changeToState('SKIP_TO_SEMICOLON');
    return false;
  }
}

class _StateSkipToSemicolon extends _State {
  _StateSkipToSemicolon(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == ';') machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateCapturingDefaultValue extends _State {
  _StateCapturingDefaultValue(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == ')' || name == ',') {
      machine.changeToState('DEFAULT');
      return true;
    }
    final scope = machine.currentScope;
    if (scope is _FunctionParameterScope) {
      if (name == 'T_STRING' || name == 'T_CONSTANT_ENCAPSED_STRING') {
        scope.addToJsForPreviousVariable(value);
      } else {
        scope.addToJsForPreviousVariable(parsedToken);
      }
    }
    return false;
  }
}

class _StateEmbeddedVariable extends _State {
  _StateEmbeddedVariable(super.machine);
  @override
  void enterState(Map<String, Object?> params) {
    machine.addJS('" + ');
  }

  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_STRING_VARNAME') {
      final scopedVariableName =
          machine.getVariableNameForScope(value, 0) ?? value;
      machine.addJS(scopedVariableName);
    }
    if (name == '}') {
      machine.addJS(' + "');
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateEndOfClass extends _State {
  _StateEndOfClass(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == '}') {
      machine.addJS('}\n\n');
    }
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateImplementsInterface extends _State {
  _StateImplementsInterface(super.machine);
  bool _first = false;
  @override
  void enterState(Map<String, Object?> params) => _first = true;
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (_first) {
      _first = false;
      machine.addJS('/*');
    }
    if (name == 'T_STRING' || name == 'T_WHITESPACE') {
      machine.addJS(value);
    }
    if (name == '{') {
      machine.addJS('*/');
      machine.changeToState('DEFAULT');
      return true;
    }
    return false;
  }
}

class _StateInterface extends _State {
  _StateInterface(super.machine);
  bool _first = false;
  @override
  void enterState(Map<String, Object?> params) => _first = true;
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (_first) {
      _first = false;
      machine.addJS('/*');
    }
    if (name == 'T_STRING' || name == 'T_WHITESPACE') {
      machine.addJS(value);
    } else {
      machine.addJS(name);
    }
    if (name == '}') {
      machine.addJS('}*/');
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateAbstract extends _State {
  _StateAbstract(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (machine.currentScope is _ClassScope) {
      machine.changeToState('ABSTRACT_FUNCTION');
      return true;
    }
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateAbstractRemove extends _State {
  _StateAbstractRemove(super.machine);
  @override
  void enterState(Map<String, Object?> params) => machine.addJS('//');
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS('//$value');
    if (name == ';') machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateRequire extends _State {
  _StateRequire(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == 'T_CONSTANT_ENCAPSED_STRING') {
      machine.addJS('// Opening the require $value');
      machine.changeToState('DEFAULT');
    }
    return false;
  }
}

class _StateNamespace extends _State {
  _StateNamespace(super.machine);
  @override
  void enterState(Map<String, Object?> params) => machine.addJS('/*');
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == ';') {
      machine.addJS('*/');
      machine.changeToState('DEFAULT');
      return false;
    }
    machine.addJS(value);
    return false;
  }
}

class _StateImportNamespace extends _State {
  _StateImportNamespace(super.machine);
  @override
  void enterState(Map<String, Object?> params) => machine.addJS('/*');
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (name == ';') {
      machine.addJS('*/');
      machine.changeToState('DEFAULT');
      return false;
    }
    machine.addJS(value);
    return false;
  }
}

class _StateUse extends _State {
  _StateUse(super.machine);
  String? _extendsName;
  @override
  void enterState(Map<String, Object?> params) => _extendsName = null;
  @override
  bool processToken(String name, String value, String parsedToken) {
    if (machine.currentScope is _GlobalScope) {
      machine.changeToState('IMPORT_NAMESPACE');
      return true;
    }
    if (machine.currentScope is _ClassScope) {
      if (name == 'T_STRING') _extendsName = value;
      if (name == ';') {
        if (_extendsName != null) {
          machine.currentScope.addParent(_extendsName!);
        }
        machine.changeToState('DEFAULT');
      }
    }
    return false;
  }
}

class _StateUnset extends _State {
  _StateUnset(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    machine.addJS('delete');
    machine.changeToState('DEFAULT');
    return false;
  }
}

class _StateString extends _State {
  _StateString(super.machine);
  @override
  bool processToken(String name, String value, String parsedToken) {
    final converted = _convertPhpValueToJsValue(value);
    if (machine.isDefined(converted)) {
      machine.addJS(machine.getDefine(converted)!);
    } else if (converted == 'static' || converted == 'self') {
      machine.addJS(machine.getClassName());
    } else if (machine.currentScope is _FunctionParameterScope) {
      machine.addJS('/*$converted*/');
    } else if (machine.currentScope is _CatchScope) {
      machine.addJS('/*$converted*/');
    } else {
      final variable =
          machine.getVariableFromScope(converted, 'CODE_SCOPE_CLASS');
      if (variable != null && (variable.flags & _flagPrivate) != 0) {
        if (machine.previousTokensMatch(['this', '.'])) {
          machine.deleteTokens(2);
        }
      }
      machine.addJS(converted);
    }
    machine.variableFlags = 0;
    machine.changeToState('DEFAULT');
    return false;
  }
}

// ---------------------------------------------------------------------------
// PHP lexer (token_get_all equivalent, covering the tokens the converter uses)
// ---------------------------------------------------------------------------
const Map<String, String> _phpKeywords = {
  'echo': 'T_ECHO',
  'print': 'T_ECHO',
  'array': 'T_ARRAY',
  'class': 'T_CLASS',
  'trait': 'T_TRAIT',
  'interface': 'T_INTERFACE',
  'function': 'T_FUNCTION',
  'fn': 'T_FUNCTION',
  'foreach': 'T_FOREACH',
  'as': 'T_AS',
  'public': 'T_PUBLIC',
  'protected': 'T_PROTECTED',
  'private': 'T_PRIVATE',
  'var': 'T_VAR',
  'static': 'T_STATIC',
  'abstract': 'T_ABSTRACT',
  'final': 'T_FINAL',
  'extends': 'T_EXTENDS',
  'implements': 'T_IMPLEMENTS',
  'use': 'T_USE',
  'namespace': 'T_NAMESPACE',
  'new': 'T_NEW',
  'return': 'T_RETURN',
  'if': 'T_IF',
  'else': 'T_ELSE',
  'elseif': 'T_ELSEIF',
  'while': 'T_WHILE',
  'for': 'T_FOR',
  'do': 'T_DO',
  'switch': 'T_SWITCH',
  'case': 'T_CASE',
  'default': 'T_DEFAULT',
  'break': 'T_BREAK',
  'continue': 'T_CONTINUE',
  'throw': 'T_THROW',
  'try': 'T_TRY',
  'catch': 'T_CATCH',
  'finally': 'T_FINALLY',
  'global': 'T_GLOBAL',
  'unset': 'T_UNSET',
  'instanceof': 'T_INSTANCEOF',
  'and': 'T_LOGICAL_AND',
  'or': 'T_LOGICAL_OR',
  'xor': 'T_LOGICAL_XOR',
  'eval': 'T_EVAL',
  'require': 'T_REQUIRE',
  'require_once': 'T_REQUIRE_ONCE',
  'include': 'T_INCLUDE',
  'include_once': 'T_INCLUDE_ONCE',
};

// Multi-character operators, longest first.
const List<List<String>> _phpOperators = [
  ['===', 'T_IS_IDENTICAL'],
  ['!==', 'T_IS_NOT_IDENTICAL'],
  ['<<=', 'T_SL_EQUAL'],
  ['>>=', 'T_SR_EQUAL'],
  ['**=', 'T_POW_EQUAL'],
  ['==', 'T_IS_EQUAL'],
  ['!=', 'T_IS_NOT_EQUAL'],
  ['<>', 'T_IS_NOT_EQUAL'],
  ['>=', 'T_IS_GREATER_OR_EQUAL'],
  ['<=', 'T_IS_SMALLER_OR_EQUAL'],
  ['&&', 'T_BOOLEAN_AND'],
  ['||', 'T_BOOLEAN_OR'],
  ['++', 'T_INC'],
  ['--', 'T_DEC'],
  ['+=', 'T_PLUS_EQUAL'],
  ['-=', 'T_MINUS_EQUAL'],
  ['*=', 'T_MUL_EQUAL'],
  ['/=', 'T_DIV_EQUAL'],
  ['.=', 'T_CONCAT_EQUAL'],
  ['%=', 'T_MOD_EQUAL'],
  ['|=', 'T_OR_EQUAL'],
  ['^=', 'T_XOR_EQUAL'],
  ['&=', 'T_AND_EQUAL'],
  ['<<', 'T_SL'],
  ['>>', 'T_SR'],
  ['->', 'T_OBJECT_OPERATOR'],
  ['=>', 'T_DOUBLE_ARROW'],
  ['::', 'T_DOUBLE_COLON'],
  ['?>', 'T_CLOSE_TAG'],
];

bool _isIdentStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
bool _isIdentPart(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);
bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isWhitespace(int c) => c == 32 || c == 9 || c == 10 || c == 13;

List<PhpToken> phpTokenize(String code) {
  final tokens = <PhpToken>[];
  var i = 0;
  final length = code.length;
  var inPhp = false;

  while (i < length) {
    if (!inPhp) {
      final open = code.indexOf('<?', i);
      if (open == -1) {
        tokens.add(PhpToken('T_INLINE_HTML', code.substring(i)));
        break;
      }
      if (open > i) {
        tokens.add(PhpToken('T_INLINE_HTML', code.substring(i, open)));
      }
      if (code.startsWith('<?php', open)) {
        i = open + 5;
      } else if (code.startsWith('<?=', open)) {
        tokens.add(PhpToken('T_ECHO', 'echo'));
        i = open + 3;
      } else {
        i = open + 2;
      }
      inPhp = true;
      continue;
    }

    final c = code.codeUnitAt(i);

    // Close tag
    if (code.startsWith('?>', i)) {
      tokens.add(PhpToken('T_CLOSE_TAG', '?>'));
      i += 2;
      inPhp = false;
      continue;
    }

    // Whitespace
    if (_isWhitespace(c)) {
      final start = i;
      while (i < length && _isWhitespace(code.codeUnitAt(i))) {
        i++;
      }
      tokens.add(PhpToken('T_WHITESPACE', code.substring(start, i)));
      continue;
    }

    // Line comments
    if (code.startsWith('//', i) || c == 35 /* # */) {
      final start = i;
      while (i < length &&
          code.codeUnitAt(i) != 10 &&
          !code.startsWith('?>', i)) {
        i++;
      }
      tokens.add(PhpToken('T_COMMENT', code.substring(start, i)));
      continue;
    }

    // Block / doc comments
    if (code.startsWith('/*', i)) {
      final start = i;
      final end = code.indexOf('*/', i + 2);
      i = end == -1 ? length : end + 2;
      final text = code.substring(start, i);
      tokens.add(
        PhpToken(text.startsWith('/**') ? 'T_DOC_COMMENT' : 'T_COMMENT', text),
      );
      continue;
    }

    // Variables
    if (c == 36 /* $ */) {
      if (i + 1 < length && _isIdentStart(code.codeUnitAt(i + 1))) {
        final start = i;
        i++;
        while (i < length && _isIdentPart(code.codeUnitAt(i))) {
          i++;
        }
        tokens.add(PhpToken('T_VARIABLE', code.substring(start, i)));
        continue;
      }
    }

    // Numbers
    if (_isDigit(c) || (c == 46 && i + 1 < length && _isDigit(code.codeUnitAt(i + 1)))) {
      final start = i;
      var isFloat = false;
      if (code.startsWith('0x', i) || code.startsWith('0X', i)) {
        i += 2;
        while (i < length && _isHex(code.codeUnitAt(i))) {
          i++;
        }
      } else {
        while (i < length && _isDigit(code.codeUnitAt(i))) {
          i++;
        }
        if (i < length && code.codeUnitAt(i) == 46) {
          isFloat = true;
          i++;
          while (i < length && _isDigit(code.codeUnitAt(i))) {
            i++;
          }
        }
        if (i < length && (code.codeUnitAt(i) == 101 || code.codeUnitAt(i) == 69)) {
          isFloat = true;
          i++;
          if (i < length &&
              (code.codeUnitAt(i) == 43 || code.codeUnitAt(i) == 45)) {
            i++;
          }
          while (i < length && _isDigit(code.codeUnitAt(i))) {
            i++;
          }
        }
      }
      tokens.add(
        PhpToken(isFloat ? 'T_DNUMBER' : 'T_LNUMBER', code.substring(start, i)),
      );
      continue;
    }

    // Identifiers / keywords
    if (_isIdentStart(c)) {
      final start = i;
      while (i < length && _isIdentPart(code.codeUnitAt(i))) {
        i++;
      }
      final word = code.substring(start, i);
      final keyword = _phpKeywords[word.toLowerCase()];
      tokens.add(PhpToken(keyword ?? 'T_STRING', word));
      continue;
    }

    // Single-quoted string
    if (c == 39 /* ' */) {
      final start = i;
      i++;
      while (i < length) {
        final ch = code.codeUnitAt(i);
        if (ch == 92 /* \ */) {
          i += 2;
          continue;
        }
        if (ch == 39) {
          i++;
          break;
        }
        i++;
      }
      tokens.add(PhpToken('T_CONSTANT_ENCAPSED_STRING', code.substring(start, i)));
      continue;
    }

    // Double-quoted string (with simple interpolation)
    if (c == 34 /* " */) {
      i = _tokenizeDoubleQuoted(code, i, tokens);
      continue;
    }

    // Multi-character operators
    var matchedOperator = false;
    for (final op in _phpOperators) {
      if (code.startsWith(op[0], i)) {
        tokens.add(PhpToken(op[1], op[0]));
        i += op[0].length;
        matchedOperator = true;
        break;
      }
    }
    if (matchedOperator) continue;

    // Single-character token
    final ch = code[i];
    tokens.add(PhpToken(ch, ''));
    i++;
  }

  return tokens;
}

bool _isHex(int c) =>
    _isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);

int _tokenizeDoubleQuoted(String code, int start, List<PhpToken> tokens) {
  final length = code.length;
  // First pass: detect interpolation.
  var hasInterpolation = false;
  var j = start + 1;
  while (j < length) {
    final ch = code.codeUnitAt(j);
    if (ch == 92) {
      j += 2;
      continue;
    }
    if (ch == 34) break;
    if (ch == 36 && j + 1 < length && _isIdentStart(code.codeUnitAt(j + 1))) {
      hasInterpolation = true;
      break;
    }
    if (ch == 123 && j + 1 < length && code.codeUnitAt(j + 1) == 36) {
      hasInterpolation = true;
      break;
    }
    j++;
  }

  if (!hasInterpolation) {
    var i = start + 1;
    while (i < length) {
      final ch = code.codeUnitAt(i);
      if (ch == 92) {
        i += 2;
        continue;
      }
      if (ch == 34) {
        i++;
        break;
      }
      i++;
    }
    tokens.add(PhpToken('T_CONSTANT_ENCAPSED_STRING', code.substring(start, i)));
    return i;
  }

  // Interpolated: emit `"` then chunks/variables then `"`.
  tokens.add(PhpToken('"', ''));
  var i = start + 1;
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(PhpToken('T_ENCAPSED_AND_WHITESPACE', buffer.toString()));
      buffer.clear();
    }
  }

  while (i < length) {
    final ch = code.codeUnitAt(i);
    if (ch == 92) {
      buffer.write(code[i]);
      if (i + 1 < length) buffer.write(code[i + 1]);
      i += 2;
      continue;
    }
    if (ch == 34) {
      i++;
      break;
    }
    if (ch == 36 && i + 1 < length && _isIdentStart(code.codeUnitAt(i + 1))) {
      flush();
      final varStart = i;
      i++;
      while (i < length && _isIdentPart(code.codeUnitAt(i))) {
        i++;
      }
      tokens.add(PhpToken('T_VARIABLE', code.substring(varStart, i)));
      continue;
    }
    if (ch == 123 && i + 1 < length && code.codeUnitAt(i + 1) == 36) {
      // {$ident}
      flush();
      tokens.add(PhpToken('T_DOLLAR_OPEN_CURLY_BRACES', r'{$'));
      i += 2;
      final nameStart = i;
      while (i < length && _isIdentPart(code.codeUnitAt(i))) {
        i++;
      }
      tokens.add(PhpToken('T_STRING_VARNAME', code.substring(nameStart, i)));
      if (i < length && code.codeUnitAt(i) == 125) {
        tokens.add(PhpToken('}', ''));
        i++;
      }
      continue;
    }
    buffer.write(code[i]);
    i++;
  }
  flush();
  tokens.add(PhpToken('"', ''));
  return i;
}
