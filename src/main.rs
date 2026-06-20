//! rxtree — reorder local C variable declarations into "reverse christmas tree"
//! order (longest declaration line first) at the start of every block scope.
//!
//! The C source is parsed into a concrete syntax tree using the `tree-sitter`
//! crate together with the `tree-sitter-c` grammar (we do not implement any C
//! parsing ourselves). For every block scope (`compound_statement`, i.e. a
//! `{ ... }` body) we collect the variable declarations that are *direct*
//! children of that block, move them to the top of the block, and sort them by
//! the length of their declaration line, longest first. When a declaration
//! spans several lines (e.g. a struct/array initializer), only its first line
//! — the one carrying the variable name — is used as the sort key; the whole
//! declaration moves as one unit.
//!
//! Usage:
//!   rxtree [--write] [FILE ...]
//!
//!   --write    rewrite files in place (default: dry run, list files that
//!              would change and print a unified-ish diff to stdout)
//!
//! With no FILE arguments it processes every *.c and *.h under net/batman-adv.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use similar::TextDiff;
use tree_sitter::{Node, Parser, Tree};

fn main() -> ExitCode {
    let mut write = false;
    let mut paths: Vec<PathBuf> = Vec::new();

    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--write" | "-w" => write = true,
            "--help" | "-h" => {
                eprintln!("usage: rxtree [--write] [FILE ...]");
                return ExitCode::SUCCESS;
            }
            _ => paths.push(PathBuf::from(arg)),
        }
    }

    if paths.is_empty() {
        paths = collect_default_files();
        if paths.is_empty() {
            eprintln!(
                "no FILE given and no *.c/*.h found under net/batman-adv \
                 (run from the kernel/batman-adv source root)"
            );
            return ExitCode::FAILURE;
        }
    }

    let mut changed_files = 0usize;
    let mut had_error = false;

    for path in &paths {
        match std::fs::read_to_string(path) {
            Ok(src) => match process_source(&src) {
                Ok(new_src) => {
                    if new_src != src {
                        changed_files += 1;
                        if write {
                            if let Err(e) = std::fs::write(path, &new_src) {
                                eprintln!("error writing {}: {e}", path.display());
                                had_error = true;
                            } else {
                                println!("rewrote {}", path.display());
                            }
                        } else {
                            print_diff(&path.display().to_string(), &src, &new_src);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("error parsing {}: {e}", path.display());
                    had_error = true;
                }
            },
            Err(e) => {
                eprintln!("error reading {}: {e}", path.display());
                had_error = true;
            }
        }
    }

    if !write {
        eprintln!("{changed_files} file(s) would change (run with --write to apply)");
    } else {
        eprintln!("{changed_files} file(s) changed");
    }

    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn collect_default_files() -> Vec<PathBuf> {
    let dir = Path::new("net/batman-adv");
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if matches!(p.extension().and_then(|s| s.to_str()), Some("c") | Some("h")) {
                out.push(p);
            }
        }
    }
    out.sort();
    out
}

fn new_parser() -> Parser {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_c::LANGUAGE.into())
        .expect("loading tree-sitter-c grammar");
    parser
}

/// Repeatedly parse the source and canonicalize the first block scope that is
/// not yet in canonical form, until a fixed point is reached. Re-parsing after
/// each edit keeps node byte offsets valid and lets nested scopes compose
/// without overlapping-edit bookkeeping. The transform is idempotent (stable
/// sort), so this terminates.
fn process_source(src: &str) -> Result<String, String> {
    let mut parser = new_parser();
    let mut text = src.to_string();

    loop {
        let tree: Tree = parser
            .parse(&text, None)
            .ok_or_else(|| "tree-sitter returned no tree".to_string())?;

        let mut blocks = Vec::new();
        collect_blocks(tree.root_node(), &mut blocks);

        let mut changed = false;
        for block in blocks {
            if let Some(new_text) = rewrite_block(&text, block) {
                text = new_text;
                changed = true;
                break; // byte offsets shifted, re-parse from scratch
            }
        }
        if !changed {
            break;
        }
    }

    Ok(text)
}

/// Depth-first collection of every `compound_statement` node. Returned in a
/// deterministic (pre-order) order so the fixed-point loop is reproducible.
fn collect_blocks<'a>(node: Node<'a>, out: &mut Vec<Node<'a>>) {
    if node.kind() == "compound_statement" {
        out.push(node);
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_blocks(child, out);
    }
}

/// Compute the canonicalized full-file text for a single block scope, or `None`
/// if the block is already canonical (or cannot be safely rewritten).
fn rewrite_block(src: &str, block: Node) -> Option<String> {
    let bytes = src.as_bytes();
    let open_brace = block.child(0)?; // first child of a compound_statement is "{"

    let mut cursor = block.walk();
    let kids: Vec<Node> = block.children(&mut cursor).collect();

    // tree-sitter-c does NOT run the C preprocessor, nor does it know kernel
    // iterator macros, so a `#if/#endif` block (and anything the parser couldn't
    // make sense of) appears as a preprocessor node or a parse error. These act
    // as hard *barriers*: declarations are sorted only *within* the region
    // between two barriers and are never moved across one. This keeps a
    // `#if`-guarded declaration from being jumped over, and confines any nodes
    // that error-recovery fabricated to their own region.
    let mut barriers: Vec<(usize, usize)> = Vec::new(); // line-aligned [start, end)
    for child in &kids {
        if is_barrier(*child) {
            barriers.push((
                line_start(bytes, child.start_byte()),
                line_end_after(bytes, child.end_byte()),
            ));
        }
    }

    // Content region of the scope: from the line after `{` to the line of `}`.
    let content_lo = line_end_after(bytes, open_brace.end_byte());
    let content_hi = match kids.last() {
        Some(c) if c.kind() == "}" => line_start(bytes, c.start_byte()),
        _ => block.end_byte(),
    };

    // Carve the content region into segments separated by the barriers.
    let mut segments: Vec<(usize, usize)> = Vec::new();
    let mut lo = content_lo;
    for &(bs, be) in &barriers {
        if bs > lo {
            segments.push((lo, bs));
        }
        lo = be.max(lo);
    }
    if content_hi > lo {
        segments.push((lo, content_hi));
    }

    // Genuine direct-child declarations (nodes inside nested blocks, `for`-init
    // clauses, struct member lists, `#if` bodies, etc. are not direct children
    // and are left untouched). A declaration whose own subtree contains an error
    // is skipped — it is most likely a mis-parse.
    let mut decls = Vec::new();
    for child in &kids {
        if child.kind() == "declaration" && !child.has_error() && !child.is_missing() {
            decls.push(*child);
        }
    }
    if decls.is_empty() {
        return None;
    }

    // Build, per segment, the insertion anchor and the sorted declaration chunks.
    let mut all_chunks: Vec<Chunk> = Vec::new();
    let mut inserts: Vec<(usize, String)> = Vec::new(); // (anchor, sorted text)

    for &(seg_lo, seg_hi) in &segments {
        let seg_decls: Vec<Node> = decls
            .iter()
            .copied()
            .filter(|d| d.start_byte() >= seg_lo && d.start_byte() < seg_hi)
            .collect();
        if seg_decls.is_empty() {
            continue;
        }

        // Leading comment region of this segment: comment(s) at the very start
        // stay put (a scope/region-level comment must not be jumped over), and
        // the sorted declarations are placed after them and any trailing blank.
        let anchor = segment_anchor(src, bytes, &kids, seg_lo, seg_hi);

        let mut chunks: Vec<Chunk> = Vec::with_capacity(seg_decls.len());
        for d in &seg_decls {
            let decl_start = line_start(bytes, d.start_byte());
            let end = line_end_after(bytes, d.end_byte());
            // Sort key: the declaration's *own* first line — never an attached
            // comment, never the continuation lines of a multi-line initializer.
            let sort_len = first_physical_line_len(&src[decl_start..end]);
            let start = comment_extended_start(src, bytes, *d, decl_start, anchor);
            chunks.push(Chunk { start, end, sort_len });
        }
        chunks.sort_by_key(|c| c.start);

        // Reverse christmas tree: longest declarator line first; stable sort
        // keeps equal-length lines in their original order.
        let mut sorted = chunks.clone();
        sorted.sort_by(|a, b| b.sort_len.cmp(&a.sort_len).then(a.start.cmp(&b.start)));
        let sorted_text: String = sorted.iter().map(|c| &src[c.start..c.end]).collect();

        inserts.push((anchor, sorted_text));
        all_chunks.extend(chunks);
    }

    if all_chunks.is_empty() {
        return None;
    }

    // Bail out (rather than corrupt) on overlapping chunks, e.g. two
    // declarations sharing one physical line ("int a; int b;").
    all_chunks.sort_by_key(|c| c.start);
    for w in all_chunks.windows(2) {
        if w[0].end > w[1].start {
            return None;
        }
    }

    // Rebuild the file: copy everything except the chunk ranges, emitting each
    // segment's sorted declaration block when its anchor position is reached.
    inserts.sort_by_key(|(a, _)| *a);
    let by_start: BTreeMap<usize, usize> =
        all_chunks.iter().map(|c| (c.start, c.end)).collect();

    let mut out = String::with_capacity(src.len() + all_chunks.iter().map(|c| c.end - c.start).sum::<usize>());
    let len = src.len();
    let mut i = 0usize;
    let mut ai = 0usize;
    while i < len {
        while ai < inserts.len() && i >= inserts[ai].0 {
            out.push_str(&inserts[ai].1);
            ai += 1;
        }
        if let Some(&end) = by_start.get(&i) {
            i = end; // skip this declaration in its original position
            continue;
        }
        let mut next = len;
        if let Some((&s, _)) = by_start.range(i + 1..).next() {
            next = next.min(s);
        }
        if ai < inserts.len() && inserts[ai].0 > i {
            next = next.min(inserts[ai].0);
        }
        out.push_str(&src[i..next]);
        i = next;
    }
    while ai < inserts.len() {
        out.push_str(&inserts[ai].1);
        ai += 1;
    }

    if out == src {
        None
    } else {
        Some(out)
    }
}

/// A direct child of a block that declarations must not be reordered across:
/// any preprocessor node (`#if`/`#endif`/…), or anything the parser flagged as
/// an error/missing or whose subtree contains one.
fn is_barrier(n: Node) -> bool {
    n.kind().starts_with("preproc") || n.is_error() || n.is_missing() || n.has_error()
}

/// Insertion anchor for a segment `[seg_lo, seg_hi)`: the start of the segment,
/// advanced past any comment(s) that lead the segment (they stay in place) and
/// any blank line that trailed them.
fn segment_anchor(src: &str, bytes: &[u8], kids: &[Node], seg_lo: usize, seg_hi: usize) -> usize {
    let mut anchor = seg_lo;
    let mut have_comment = false;
    for child in kids {
        let cls = line_start(bytes, child.start_byte());
        if cls < anchor {
            continue;
        }
        if cls >= seg_hi {
            break;
        }
        if child.kind() != "comment" {
            break; // first declaration or statement of the segment
        }
        anchor = line_end_after(bytes, child.end_byte());
        have_comment = true;
    }
    if have_comment {
        while anchor < seg_hi {
            let le = line_end_after(bytes, anchor);
            if src[anchor..le].trim().is_empty() {
                anchor = le;
            } else {
                break;
            }
        }
    }
    anchor
}

#[derive(Clone, Copy)]
struct Chunk {
    /// Start of the relocatable text (line start of the earliest attached
    /// comment, or of the declaration itself when there is no such comment).
    start: usize,
    /// Just past the newline ending the declaration.
    end: usize,
    /// Char length of the declaration's own first physical line — the sort key.
    sort_len: usize,
}

/// Length in characters of the first physical line of `s` (newline excluded).
fn first_physical_line_len(s: &str) -> usize {
    s.split('\n')
        .next()
        .unwrap_or("")
        .trim_end_matches('\r')
        .chars()
        .count()
}

/// Walk backwards from a declaration over standalone comment lines that sit
/// directly in front of it (no blank line in between) and return the line-start
/// byte offset where the relocatable chunk should begin. A trailing comment on
/// a code line ("x = 1; /* note */") is not standalone and is not pulled in.
/// Comments at or above `leading_floor` (the scope's leading comment region)
/// are never pulled in — they stay at the top of the scope.
fn comment_extended_start(
    src: &str,
    bytes: &[u8],
    decl: Node,
    decl_line_start: usize,
    leading_floor: usize,
) -> usize {
    let mut front = decl;
    let mut start = decl_line_start;
    while let Some(prev) = front.prev_sibling() {
        if prev.kind() != "comment" {
            break;
        }
        let prev_line_start = line_start(bytes, prev.start_byte());
        // Don't reach into the scope's leading comment region.
        if prev_line_start < leading_floor {
            break;
        }
        // Must be the only thing on its line(s): only whitespace before it.
        if !src[prev_line_start..prev.start_byte()].trim().is_empty() {
            break;
        }
        // Must be directly attached: no blank line separating it from the chunk.
        if src[prev.end_byte()..front.start_byte()].matches('\n').count() > 1 {
            break;
        }
        front = prev;
        start = prev_line_start;
    }
    start
}

/// Byte offset of the start of the line containing `i` (just after the
/// preceding newline, or 0).
fn line_start(bytes: &[u8], mut i: usize) -> usize {
    while i > 0 && bytes[i - 1] != b'\n' {
        i -= 1;
    }
    i
}

/// Byte offset just past the newline that ends the line containing/following
/// `i` (or end-of-file). `i` is typically an exclusive node end.
fn line_end_after(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() && bytes[i] != b'\n' {
        i += 1;
    }
    if i < bytes.len() {
        i + 1
    } else {
        i
    }
}

/// Unified diff for the dry-run view, rendered with the `similar` crate.
fn print_diff(path: &str, old: &str, new: &str) {
    let diff = TextDiff::from_lines(old, new);
    print!(
        "{}",
        diff.unified_diff()
            .context_radius(3)
            .header(&format!("a/{path}"), &format!("b/{path}"))
    );
}
