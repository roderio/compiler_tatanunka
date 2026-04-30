# Conj: A Minimal Programming Language Compiler

## Overview

**Conj** is a small, experimental programming language compiler and interpreter written in C++. It demonstrates core compiler construction techniques including lexical analysis, syntax parsing, semantic analysis, code generation, and optimization.

The project uses industry-standard tools—**re2c** for lexer generation and **Bison** (GNU yacc) for parser generation—to build a complete LALR(1) bottom-up parser that translates source code into an executable intermediate representation.

## What It Does

Conj compiles source programs into an Abstract Syntax Tree (AST) based on expression types, then evaluates them. The compiler supports:

- **Data Types**: Numbers (integers), strings, and pointers
- **Control Flow**: Loops (`while`-like constructs), conditional logic
- **Functions**: Definition, parameters, recursion, and calls
- **Operations**: 
  - Arithmetic: addition, negation
  - Comparison: equality checking
  - Logical: short-circuit AND/OR operations
  - Memory: address-of and dereference operators
  - Assignment: copy operations with move semantics
- **Variables**: Local variables, parameters, and identifiers with proper scoping

## Architecture

The compiler pipeline consists of three main stages:

### 1. Lexical Analysis (Tokenization)

The lexer (`conj.cc.re`) is generated from re2c specifications and converts raw source text into a token stream. It handles:
- Keyword and identifier recognition
- Numeric and string literal parsing
- Operator tokenization
- Whitespace and comment handling

### 2. Syntax Analysis (Parsing)

The parser (`conj.y`) is an LALR(1) Bison grammar that:
- Enforces language syntax rules
- Builds an Abstract Syntax Tree (AST)
- Performs error recovery with detailed diagnostics
- Tracks location information (file, line, column) for error reporting

The grammar defines expression precedence and associativity, ensuring correct evaluation order.

### 3. Semantic Analysis & Code Generation

The parser actions simultaneously:
- Perform type checking and semantic validation
- Maintain symbol tables for identifiers (functions, variables, parameters)
- Apply compile-time optimizations
- Generate the intermediate expression representation

## Optimization: Constant Folding

**Constant folding** is implemented to evaluate constant expressions at compile time. When the compiler encounters an operation whose operands are known constants (e.g., `3 + 5`), it computes the result during compilation rather than deferring to runtime. This:
- Reduces runtime computation
- Eliminates dead code paths
- Makes program execution faster

For example, `let x = 2 + 3;` becomes `let x = 5;` in the compiled output.

## Building

```bash
make
```

The build process:
1. Generates the lexer from `conj.cc.re` using re2c
2. Generates the parser from `conj.y` using Bison
3. Compiles the C++ implementation
4. Links everything into the `conj` executable

## Running

```bash
./conj < program.txt
```

The compiler reads a program from standard input and outputs the compiled expression tree.

## Project Files

- **conj.y** — Bison grammar specification (syntax rules and semantic actions)
- **conj.cc.re** — re2c lexer specification
- **conj.cc** — Generated C++ parser implementation (from conj.y)
- **conj.tab.h / conj.tab.c** — Bison-generated parser table headers
- **location.hh** — Location tracking for error diagnostics
- **conj** — Compiled executable
- **first_test.txt** — Sample test programs

## Technical Highlights

- **Modern C++**: Uses variant types, move semantics, and template metaprogramming
- **LALR(1) Parsing**: Efficient shift-reduce parsing with single-token lookahead
- **Proper Diagnostics**: Tracks source locations for meaningful error messages
- **Clean Separation**: Lexer, parser, and semantics neatly decoupled

## Future Considerations

The architecture is extensible for:
- Type system enhancements
- Additional optimization passes
- Backend code generation (to native code or bytecode)
- Module system for multi-file programs
- Standard library integration

---