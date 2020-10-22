
import strformat
import system
import tables
import hashes
import options

import ternary_tree

import ./data
import ./types
import ./errors
import ./gen_code

proc nativeList(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  var args = initTernaryTreeList[CirruData](@[])
  for node in exprList:
    args = args.append interpret(node, scope)
  return CirruData(kind: crDataList, listVal: args)

proc nativeIf*(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  if (exprList.len < 2):
    raiseEvalError(fmt"No arguments for if", exprList)
  elif (exprList.len == 2):
    let node = exprList[0]
    let cond = interpret(node, scope)
    if cond.kind == crDataBool:
      if cond.boolVal:
        return interpret(exprList[1], scope)
      else:
        return CirruData(kind: crDataNil)
    else:
      raiseEvalError("Not a bool in if", node)
  elif (exprList.len == 3):
    let node = exprList[0]
    let cond = interpret(node, scope)
    if cond.kind == crDataBool:
      if cond.boolVal:
        return interpret(exprList[1], scope)
      else:
        return interpret(exprList[2], scope)
    else:
      raiseEvalError("Not a bool in if", node)
  else:
    raiseEvalError("Too many arguments for if", exprList)

proc nativeComment(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  return CirruData(kind: crDataNil)

proc nativeMap*(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  var value = initTable[CirruData, CirruData]()
  for pair in exprList:
    if pair.kind != crDataList:
      raiseEvalError("Table requires nested children pairs", pair)
    if pair.len() != 2:
      raiseEvalError("Each pair of table contains 2 elements", pair)
    let k = interpret(pair[0], scope)
    let v = interpret(pair[1], scope)
    value.add(k, v)
  return CirruData(kind: crDataMap, mapVal: initTernaryTreeMap(value))

proc processArguments(definedArgs: CirruData, passedArgs: seq[CirruData]): CirruDataScope =
  var argsScope: CirruDataScope

  var counter = 0
  if definedArgs.kind != crDataList:
    raiseEvalError("Expected a list as arguments", definedArgs)
  let splitPosition = definedArgs.listVal.findIndex(proc(item: CirruData): bool =
    item.kind == crDataSymbol and item.symbolVal == "&"
  )

  if splitPosition >= 0:
    if passedArgs.len < splitPosition:
      raiseEvalError("No enough arguments", definedArgs)
    if splitPosition != (definedArgs.len - 2):
      raiseEvalError("& should appear before last argument", definedArgs)
    for idx in 0..<splitPosition:
      let definedArgName = definedArgs[idx]
      if definedArgName.kind != crDataSymbol:
        raiseEvalError("Expects arg in symbol", definedArgName)
      argsScope = argsScope.assoc(definedArgName.symbolVal, passedArgs[idx])
    var varList = initTernaryTreeList[CirruData](@[])
    for idx in splitPosition..<passedArgs.len:
      varList = varList.append passedArgs[idx]
    let varArgName = definedArgs[definedArgs.len - 1]
    if varArgName.kind != crDataSymbol:
      raiseEvalError("Expected var arg in symbol", varArgName)
    argsScope = argsScope.assoc(varArgName.symbolVal, CirruData(kind: crDataList, listVal: varList))
    return argsScope

  else:
    var counter = 0
    if definedArgs.len != passedArgs.len:
      raiseEvalError(fmt"Args length mismatch: {definedArgs.len} {passedArgs.len}", definedArgs)
    definedArgs.listVal.each(proc(arg: CirruData): void =
      if arg.kind != crDataSymbol:
        raiseEvalError("Expects arg in symbol", arg)
      argsScope = argsScope.assoc(arg.symbolVal, passedArgs[counter])
      counter += 1
    )
    return argsScope

proc nativeDefn(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  # echo "defn: ", $CirruData(kind: crDataList, listVal: initTernaryTreeList(exprList))
  # writeStackTrace()

  let f = proc(xs: seq[CirruData], interpret2: EdnEvalFn, scope2: CirruDataScope): CirruData =
    let argsList = exprList[1]

    let innerScope = scope.merge(processArguments(argsList, xs))

    var ret = CirruData(kind: crDataNil)
    for child in exprList[2..^1]:
      ret = interpret(child, innerScope)
    if ret.isRecur:
      ret.fnReady = true
    return ret

  let code = RefCirruData(kind: crDataList, listVal: initTernaryTreeList(exprList))
  return CirruData(kind: crDataFn, fnVal: f, fnCode: code)

proc nativeFn(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  let f = proc(xs: seq[CirruData], interpret2: EdnEvalFn, scope2: CirruDataScope): CirruData =
    let argsList = exprList[0]

    let innerScope = scope.merge(processArguments(argsList, xs))

    var ret = CirruData(kind: crDataNil)
    for child in exprList[1..^1]:
      ret = interpret(child, innerScope)
    return ret

  let code = RefCirruData(kind: crDataList, listVal: initTernaryTreeList(exprList))
  return CirruData(kind: crDataFn, fnVal: f, fnCode: code)

proc nativeLet(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  var letScope = scope
  if exprList.len < 1:
    raiseEvalError("No enough code for let, too short", exprList)
  let pairs = exprList[0]
  let body = exprList[1..^1]
  if pairs.kind != crDataList:
    raiseEvalError("Expect bindings in a list", pairs)
  for pair in pairs:
    if pair.kind != crDataList:
      raiseEvalError("Expect binding in a list", pair)
    if pair.len != 2:
      raiseEvalError("Expect binding in length 2", pair)
    let name = pair[0]
    let value = pair[1]
    if name.kind != crDataSymbol:
      raiseEvalError("Expecting binding name in string", name)
    letScope = letScope.assoc(name.symbolVal, interpret(value, letScope))
  result = CirruData(kind: crDataNil)
  for child in body:
    result = interpret(child, letScope)

proc nativeLoop(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  var loopScope = scope
  if exprList.len < 1: raiseEvalError("No enough code for loop, too short", exprList)
  let pairs = exprList[0]
  let body = exprList[1..^1]
  if not pairs.isList: raiseEvalError("Expect bindings in a list", pairs)
  for pair in pairs:
    if not pair.isList: raiseEvalError("Expect binding in a list", pair)
    if pair.len != 2: raiseEvalError("Expect binding in length 2", pair)
    let name = pair[0]
    let value = pair[1]
    if not name.isSymbol: raiseEvalError("Expecting binding name in string", name)
    loopScope = loopScope.assoc(name.symbolVal, interpret(value, loopScope))
  var ret = CirruData(kind: crDataNil)
  for child in body:
    ret = interpret(child, loopScope)
  while ret.isRecur:
    if ret.args.len != pairs.len:
      raiseEvalError(fmt"recur args {ret.args.len} != {pairs.len}", exprList)
    var idx = 0
    for pair in pairs:
      if not pair.isList: raiseEvalError("Expect binding in a list", pair)
      if pair.len != 2: raiseEvalError("Expect binding in length 2", pair)
      let name = pair[0]
      if not name.isSymbol: raiseEvalError("Expecting binding name in string", name)
      loopScope = loopScope.assoc(name.symbolVal, ret.args[idx])
      idx = idx + 1

    for child in body:
      ret = interpret(child, loopScope)
  ret

proc nativeDo*(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  result = CirruData(kind: crDataNil)
  for child in exprList:
    result = interpret(child, scope)

# TODO, symbols in macros refers to define scope
proc attachScope(exprList: CirruData, scope: CirruDataScope): CirruData =
  case exprList.kind
  of crDataSymbol:
    return CirruData(kind: crDataSymbol, symbolVal: exprList.symbolVal, ns: exprList.ns, scope: some(scope))
  of crDataList:
    var list = initTernaryTreeList[CirruData](@[])
    for item in exprList:
      list = list.append attachScope(item, scope)
    return CirruData(kind: crDataList, listVal: list)
  of crDataNil: return exprList
  of crDataBool: return exprList
  of crDataNumber: return exprList
  of crDataKeyword: return exprList
  of crDataString: return exprList
  else:
    raiseEvalError("Unexpected data for attaching", exprList)

proc nativeQuote(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  if exprList.len != 1:
    raiseEvalError("quote expects 1 argument", exprList)
  let code = attachScope(exprList[0], scope)
  return code

proc replaceExpr(exprList: CirruData, interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  case exprList.kind
  of crDataSymbol: return exprList
  of crDataString: return exprList
  of crDataNumber: return exprList
  of crDataBool: return exprList
  of crDataKeyword: return exprList
  of crDataList:
    if exprList.len == 0:
      return CirruData(kind: crDataList, listVal: initTernaryTreeList[CirruData](@[]))
    if exprList[0].isSymbol and exprList[0].symbolVal == "~":
      if exprList.len != 2:
        raiseEvalError "Expected 1 argument in ~ of quote-replace", exprList
      return interpret(exprList[1], scope)

    var list = initTernaryTreeList[CirruData](@[])
    for item in exprList:
      if item.kind == crDataList:
        let head = item[0]
        if head.symbolVal == "~":
          if item.len != 2:
            raiseEvalError "Expected 1 argument in ~ of quote-replace", item
          list = list.append interpret(item[1], scope)
        elif head.symbolVal == "~@":
          if item.len != 2:
            raiseEvalError "Expected 1 argument in ~@ of quote-replace", item
          let xs = interpret(item[1], scope)
          if xs.kind != crDataList:
            raiseEvalError "Expected list for ~@ of quote-replace", xs
          for x in xs:
            list = list.append x
        else:
          list = list.append replaceExpr(item, interpret, scope)
      else:
        list = list.append replaceExpr(item, interpret, scope)
    return CirruData(kind: crDataList, listVal: list)
  else:
    raiseEvalError("Unknown data in expr", exprList)

proc nativeQuoteReplace(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  if exprList.len != 1:
    raiseEvalError(fmt"quote-replace expects 1 argument, got {exprList.len}", exprList)

  let ret = replaceExpr(attachScope(exprList[0], scope), interpret, scope)
  if not checkExprStructure(ret):
    raiseEvalError("Unexpected structure from quote-replace", ret)
  ret

proc nativeDefMacro(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  let f = proc(xs: seq[CirruData], callingFn: EdnEvalFn, callingScope: CirruDataScope): CirruData =
    let argsList = exprList[1]
    let innerScope = scope.merge(processArguments(argsList, xs))

    var ret = CirruData(kind: crDataNil)
    for child in exprList[2..^1]:
      ret = interpret(child, innerScope)
    if ret.isList.not and ret.isRecur.not and ret.isSymbol.not:
      raiseEvalError("Expected list or recur from defmacro", ret)
    return ret

  let code = RefCirruData(kind: crDataList, listVal: initTernaryTreeList(exprList))
  return CirruData(kind: crDataMacro, macroVal: f, macroCode: code)

proc nativeAssert(exprList: seq[CirruData], interpret: EdnEvalFn, scope: CirruDataScope): CirruData =
  if exprList.len != 2:
    raiseEvalError("assert expects 1 argument", exprList)
  let message = interpret(exprList[0], scope)
  if message.kind != crDataString:
    raiseEvalError("Expected assert message in string", exprList[0])
  let target = interpret(exprList[1], scope)
  if target.kind != crDataBool:
    raiseEvalError("Expected assert target in bool", exprList[1])
  if not target.boolVal:
    raiseEvalError(message.stringVal, exprList)

proc loadCoreSyntax*(programData: var Table[string, ProgramFile], interpret: EdnEvalFn) =
  programData[coreNs].defs["[]"] = CirruData(kind: crDataSyntax, syntaxVal: nativeList, syntaxCode: fakeNativeCode("[]"))
  programData[coreNs].defs["assert"] = CirruData(kind: crDataSyntax, syntaxVal: nativeAssert, syntaxCode: fakeNativeCode("assert"))
  programData[coreNs].defs["quote-replace"] = CirruData(kind: crDataSyntax, syntaxVal: nativeQuoteReplace, syntaxCode: fakeNativeCode("quote-replace"))
  programData[coreNs].defs["defmacro"] = CirruData(kind: crDataSyntax, syntaxVal: nativeDefMacro, syntaxCode: fakeNativeCode("defmacro"))
  programData[coreNs].defs[";"] = CirruData(kind: crDataSyntax, syntaxVal: nativeComment, syntaxCode: fakeNativeCode(";"))
  programData[coreNs].defs["do"] = CirruData(kind: crDataSyntax, syntaxVal: nativeDo, syntaxCode: fakeNativeCode("do"))
  programData[coreNs].defs["if"] = CirruData(kind: crDataSyntax, syntaxVal: nativeIf, syntaxCode: fakeNativeCode("if"))
  programData[coreNs].defs["defn"] = CirruData(kind: crDataSyntax, syntaxVal: nativeDefn, syntaxCode: fakeNativeCode("defn"))
  programData[coreNs].defs["fn"] = CirruData(kind: crDataSyntax, syntaxVal: nativeFn, syntaxCode: fakeNativeCode("fn"))
  programData[coreNs].defs["let"] = CirruData(kind: crDataSyntax, syntaxVal: nativeLet, syntaxCode: fakeNativeCode("let"))
  programData[coreNs].defs["quote"] = CirruData(kind: crDataSyntax, syntaxVal: nativeQuote, syntaxCode: fakeNativeCode("quote"))
  programData[coreNs].defs["{}"] = CirruData(kind: crDataSyntax, syntaxVal: nativeMap, syntaxCode: fakeNativeCode("{}"))
  programData[coreNs].defs["loop"] = CirruData(kind: crDataSyntax, syntaxVal: nativeLoop, syntaxCode: fakeNativeCode("loop"))