
import os
import cirruParser
import sequtils
from strutils import join
import strformat
import cirruInterpreter/types

proc interpret(expr: CirruNode): CirruValue =
  if expr.kind == cirruString:
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
        else:
          raise newException(InterpretError, fmt"Unknown {head.text}")
      else:
        echo "TODO"

proc main(): void =
  case paramCount()
  of 0:
    echo "No file to eval!"
  of 1:
    let program = parseCirru readFile(paramStr(1))
    case program.kind
    of cirruString:
      echo "impossible"
    of cirruSeq:
      discard program.list.mapIt(interpret(it))
  else:
    echo "Not sure"

main()
