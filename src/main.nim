
import os
import re
import cirruParser
import cirruParser/types
import cirruParser/helpers
import sequtils
from strutils import join, parseInt
import math
import strformat
import cirruInterpreter/interpreterTypes

var interpret: proc(expr: CirruNode): CirruValue

proc evalAdd(exprList: seq[CirruNode]): CirruValue =
  var ret = 0
  for v in exprList[1..^1].map(interpret):
    if v.kind == crValueInt:
      ret += v.intVal
    else:
      raise newException(InterpretError, fmt"Not a number {v.kind}")
  return CirruValue(kind: crValueInt, intVal: ret)

proc evalMinus(exprList: seq[CirruNode]): CirruValue =
  if (exprList.len == 1):
    return CirruValue(kind: crValueInt, intVal: 0)
  elif (exprList.len == 2):
    let ret = interpret(exprList[1])
    if ret.kind == crValueInt:
      return ret
    else:
      raise newException(InterpretError, fmt"Not a number {ret.kind}")
  else:
    let x0 = interpret(exprList[1])
    var ret = 0
    if x0.kind == crValueInt:
      ret = x0.intVal
    else:
      raise newException(InterpretError, fmt"Not a number {x0.kind}")
    for v in exprList[2..^1].map(interpret):
      if v.kind == crValueInt:
        ret -= v.intVal
      else:
        raise newException(InterpretError, fmt"Not a number {v.kind}")
    return CirruValue(kind: crValueInt, intVal: ret)

interpret = proc (expr: CirruNode): CirruValue =
  if expr.kind == cirruString:
    if match(expr.text, re"\d+"):
      return CirruValue(kind: crValueInt, intVal: parseInt(expr.text))
    else:
      return CirruValue(kind: crValueString, stringVal: expr.text)
  else:
    if expr.list.len == 0:
      return
    else:
      let head = expr.list[0]
      case head.kind
      of cirruString:
        case head.text
        of "println":
          echo expr.list[1..^1].map(interpret).map(toString).join(" ")
        of "+":
          return evalAdd(expr.list)
        of "-":
          return evalMinus(expr.list)
        else:
          raise newException(InterpretError, fmt"Unknown {head.text}")
      else:
        echo "TODO"

proc main(): void =
  case paramCount()
  of 0:
    echo "No file to eval!"
  of 1:
    let sourcePath = paramStr(1)
    let source = readFile sourcePath
    try:
      let program = parseCirru source
      case program.kind
      of cirruString:
        echo "impossible"
      of cirruSeq:
        discard program.list.mapIt(interpret(it))
    except CirruParseError as e:
      echo formatParserFailure(source, e.msg, sourcePath, e.line, e.column)
  else:
    echo "Not sure"

main()