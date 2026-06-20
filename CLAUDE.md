# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`rxtree` is a single-purpose CLI that rewrites C source so local variable
declarations follow the kernel/netdev **"reverse christmas tree"** convention:
within each block scope, declarations are moved to the top and sorted by line
length, longest first. It was built to tidy the sibling `batman-adv` tree (the
default target when no files are given is `net/batman-adv/*.{c,h}`).

It parses C with the **`tree-sitter`** + **`tree-sitter-c`** crates (a real AST —
no hand-rolled C parsing) and renders dry-run diffs with **`similar`**. All logic
lives in `src/main.rs`.

## Commands

```sh
cargo build                                   # debug build -> target/debug/rxtree
cargo run -- [--write] [--single] [FILE ...]  # run on FILEs (or default tree)
cargo build --release                         # release profile (LTO, stripped)
```

CLI behaviour:
- No `FILE` args → processes `net/batman-adv/*.{c,h}` relative to the CWD.
- Default is a **dry run**: prints a unified diff per file, changes nothing.
- `--write` / `-w` → rewrite files in place.
- `--single` → first split any line declaring several variables into one
  declaration per line (`struct foo *a, b;` → `struct foo *a;` / `struct foo b;`),
  then sort.

There is no test suite. The working validation method (used throughout
development) is: copy a tree, `--write` it, then assert the rewrite **preserves
the sorted line multiset** (`diff <(sort orig) <(sort new)` — pure relocation,
nothing added/dropped/mutated) and is **idempotent** (a second pass reports 0
changes). Under `--single` the line multiset legitimately changes, so validate
via idempotency instead.

## Architecture (all in `src/main.rs`)

The transform is **idempotent** and either pure-relocation (default) or
relocation-after-splitting (`--single`); these invariants are what make the
multiset/idempotency checks above meaningful, so preserve them when editing.

- `process_source(src, single)` — the driver. If `single`, runs
  `split_multi_declarations` once first. Then runs a **fixed-point loop**:
  parse → find the first block that `rewrite_block` changes → apply → re-parse,
  until stable. Re-parsing after each edit keeps node byte offsets valid and
  lets nested scopes compose without overlap bookkeeping.
- `rewrite_block(src, block)` — the core. Splits a scope into **segments at
  barriers**, then within each segment sorts the declarations and places them at
  the segment start. Returns the new whole-file text or `None` if unchanged.
- `split_multi_declarations` (`--single` only) — rewrites multi-declarator
  declarations in place, repeating the shared leading type and keeping per-
  declarator parts (`*`, `[]`, `= init`) with their variable.

### Why it is full of special cases

`tree-sitter-c` does **not** run the C preprocessor and does not know kernel
iterator macros, so it mis-parses common kernel code. The design centres on not
trusting or corrupting those regions:

- **Barriers** (`is_barrier`): any direct child that is a preprocessor node
  (`#if`/`#endif`/…) or a parse error/missing node. Declarations are **never
  reordered across a barrier** — they sort only within the segment between two
  barriers. This both respects `#ifdef`-guarded declarations and confines nodes
  that error-recovery fabricated (e.g. `else eth_zero_addr(dst);` mis-parsed as a
  `declaration`) to their own segment, where a lone declaration won't move.
- **Comments**: a comment leading a segment stays at the top (`segment_anchor`);
  a comment directly in front of a *mid-segment* declaration travels with it
  (`comment_extended_start`); a trailing comment stays on its code line.
- **Sort key** is the declaration's *own first physical line*
  (`first_physical_line_len`) — never an attached comment and never the
  continuation lines of a multi-line struct/array initializer.
- Only **direct-child `declaration` nodes** of a `compound_statement` are touched
  (not struct members, `for`-init clauses, `#if` bodies, or globals). Nodes whose
  subtree `has_error()` are skipped. Overlapping chunks (two declarations on one
  physical line) abort the rewrite rather than risk corruption. `--single` will
  not split an anonymous `struct {...} a, b;` (duplicating the body would create
  distinct types).

### Known limitations (intentional)

- Sorting by line length ignores data dependencies between initializers; a later
  declaration whose initializer uses an earlier one can be reordered into a
  use-before-init. Review diffs before `--write`ing broadly.
- Declarations *inside* a `#if … #endif` block are not sorted among themselves
  (they are children of the `preproc_if`, not the scope).
