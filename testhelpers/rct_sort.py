#!/usr/bin/env python3
"""
Reorder variable declaration blocks at the start of each C function body
using reverse-christmas-tree (longest line first). When a dependency between
declarations would prevent strict RCT ordering (a longer decl's initializer
references a shorter decl), the longer decl's initializer is moved out of the
declaration into a separate assignment statement at the start of the function
body.
"""

import re
import sys


CONTROL_KEYWORDS = {
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
    'return', 'goto', 'break', 'continue',
}

STORAGE_MODIFIERS = {'static', 'const', 'volatile', 'extern', 'register', 'inline'}

SINGLE_WORD_TYPES = {
    'int', 'char', 'bool', 'void', 'size_t', 'ssize_t',
    's8', 's16', 's32', 's64', 'u8', 'u16', 'u32', 'u64',
    'atomic_t', 'atomic64_t', 'spinlock_t',
    '__be16', '__be32', '__be64', '__le16', '__le32', '__le64',
    'batadv_dat_addr_t', 'gfp_t', 'loff_t', 'dma_addr_t', 'ktime_t',
    'netdev_tx_t', 'netdev_features_t', 'sockptr_t', 'seqcount_t',
    'refcount_t', 'kuid_t', 'kgid_t', 'umode_t', 'pid_t',
    'fl_owner_t', '__sum16', '__wsum', '__poll_t', 'tpacket_req_u',
}

MULTI_WORD_TYPES = {'unsigned', 'signed', 'long', 'short', 'struct', 'union', 'enum'}


def looks_like_decl(line):
    s = line.lstrip()
    if not s or s.startswith('//') or s.startswith('/*') or s.startswith('*'):
        return False
    if s.startswith('#'):
        return False
    words = s.split()
    if not words:
        return False
    while words and words[0] in STORAGE_MODIFIERS:
        words.pop(0)
    if not words:
        return False
    type_word = words[0]
    if type_word in CONTROL_KEYWORDS:
        return False
    if type_word in MULTI_WORD_TYPES:
        return len(words) >= 2
    if type_word in SINGLE_WORD_TYPES:
        return len(words) >= 2
    if type_word.endswith('_t') and re.match(r'^[a-z_][a-z0-9_]*$', type_word):
        return len(words) >= 2
    if re.match(r'^batadv_[a-z_]+$', type_word):
        return len(words) >= 2
    return False


def line_terminates_decl(line):
    s = line.rstrip()
    s = re.sub(r'\s*/\*[^*]*\*/\s*$', '', s)
    s = re.sub(r'\s*//.*$', '', s)
    s = s.rstrip()
    return s.endswith(';') or s.endswith('};')


def skip_leading_comment(lines, start_idx):
    """Skip over a leading block comment at the top of a function body.
    Returns the index of the first line after the comment, or start_idx if no
    leading comment is present."""
    i = start_idx
    if i >= len(lines):
        return i
    s = lines[i].lstrip()
    if not s.startswith('/*'):
        return start_idx
    # Find end of comment
    j = i
    while j < len(lines):
        if '*/' in lines[j]:
            return j + 1
        j += 1
    return start_idx  # malformed; bail


def parse_decl_block(lines, start_idx):
    start_idx = skip_leading_comment(lines, start_idx)
    decls = []
    i = start_idx
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            break
        if not looks_like_decl(line):
            break
        decl_lines = [line]
        j = i
        while not line_terminates_decl(lines[j]):
            j += 1
            if j >= len(lines):
                break
            decl_lines.append(lines[j])
        decls.append({
            'first_line': line,
            'all_lines': decl_lines,
        })
        i = j + 1
    return decls, i


def extract_declared_name(decl_text):
    s = decl_text.strip().rstrip(';').strip()
    # Strip trailing comment
    s = re.sub(r'\s*/\*[^*]*\*/\s*$', '', s).rstrip()
    s = re.split(r'[\[=]', s, maxsplit=1)[0]
    tokens = s.split()
    if not tokens:
        return None
    name = tokens[-1].lstrip('*')
    if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', name):
        return None
    return name


def extract_initializer_refs(decl_text):
    idx = decl_text.find('=')
    if idx < 0:
        return set()
    init = decl_text[idx + 1:]
    # Strip trailing comment
    init = re.sub(r'/\*[^*]*\*/', '', init)
    init = re.sub(r'//.*$', '', init)
    # Find identifiers NOT preceded by member-access operators (->, .)
    refs = set()
    for m in re.finditer(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b', init):
        # Look at chars immediately before the match
        start = m.start()
        prefix = init[max(0, start - 2):start]
        if prefix.endswith('->') or prefix.endswith('.'):
            continue
        refs.add(m.group())
    return refs


def has_initializer(line):
    # Check if line has '=' that introduces initializer (not == or != or <=)
    return bool(re.search(r'(?<![=!<>])=(?!=)', line))


def strip_initializer(first_line):
    """Convert 'int x = expr;' to 'int x;', preserving indent/trailing comment."""
    s = first_line.rstrip('\n')
    # Capture: indent, decl-part-before-=, init-part-after-=, trailing comment after ;
    m = re.match(r'^(\s*)(.*?)\s*=\s*(.+?);\s*(/\*[^*]*\*/)?\s*$', s)
    if not m:
        return first_line
    indent, decl_part, init_part, comment = m.group(1), m.group(2), m.group(3), m.group(4) or ''
    if comment:
        return f"{indent}{decl_part}; {comment}\n"
    return f"{indent}{decl_part};\n"


def build_assignment(first_line, body_indent='\t'):
    """Build assignment statement extracted from a single-line init decl."""
    s = first_line.rstrip('\n')
    m = re.match(r'^(\s*)(.*?)\s*=\s*(.+?);\s*(/\*[^*]*\*/)?\s*$', s)
    if not m:
        return None
    decl_part, init_part = m.group(2), m.group(3)
    # Variable name: last token of decl_part, strip leading * and trailing [..]
    decl_part_clean = re.split(r'\[', decl_part, maxsplit=1)[0].rstrip()
    tokens = decl_part_clean.split()
    if not tokens:
        return None
    name = tokens[-1].lstrip('*')
    if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', name):
        return None
    return f"{body_indent}{name} = {init_part};\n"


def is_extractable(decl):
    """Single-line decl with simple initializer."""
    if len(decl['all_lines']) != 1:
        return False
    line = decl['first_line']
    if not has_initializer(line):
        return False
    # Don't extract static / const / register decls
    s = line.lstrip()
    first_word = s.split()[0] if s.split() else ''
    if first_word in ('static', 'const', 'register'):
        return False
    # Verify we can build both stripped decl and assignment
    if not build_assignment(line):
        return False
    return True


def compute_deps(decls, name_to_idx, skip_extracted=None):
    skip_extracted = skip_extracted or set()
    n = len(decls)
    deps = [set() for _ in range(n)]
    for i, d in enumerate(decls):
        if i in skip_extracted:
            continue
        refs = extract_initializer_refs(d['first_line'])
        for r in refs:
            j = name_to_idx.get(r)
            if j is not None and j != i:
                deps[i].add(j)
    return deps


def line_len(decls, i, to_extract):
    if i in to_extract:
        return len(strip_initializer(decls[i]['first_line']).rstrip('\n'))
    return len(decls[i]['first_line'].rstrip('\n'))


def detect_extractions(decls, name_to_idx):
    """Decide which decls to extract: iteratively pick the one whose extraction
    resolves the most RCT violations, until no violations remain."""
    n = len(decls)
    to_extract = set()

    def deps_now():
        return compute_deps(decls, name_to_idx, skip_extracted=to_extract)

    while True:
        deps = deps_now()
        # Find violations: i depends on j AND len(i) > len(j)
        violation_count = {}
        for i in range(n):
            if i in to_extract:
                continue
            for j in deps[i]:
                if line_len(decls, i, to_extract) > line_len(decls, j, to_extract):
                    violation_count[i] = violation_count.get(i, 0) + 1
        if not violation_count:
            break
        # Pick the longest-line violator (most likely to be the problem)
        # that is_extractable
        candidates = [i for i in violation_count if is_extractable(decls[i])]
        if not candidates:
            # No extractable violator; give up
            break
        candidates.sort(key=lambda i: -line_len(decls, i, to_extract))
        to_extract.add(candidates[0])
    return to_extract


def topo_rct_sort(decls, deps, to_extract):
    n = len(decls)
    placed = [False] * n
    placed_set = set()
    result = []
    while len(result) < n:
        ready = [i for i in range(n) if not placed[i] and deps[i].issubset(placed_set)]
        if not ready:
            return list(range(n))  # fallback
        ready.sort(key=lambda i: (-line_len(decls, i, to_extract), i))
        chosen = ready[0]
        result.append(chosen)
        placed[chosen] = True
        placed_set.add(chosen)
    return result


def find_body_starts(lines):
    results = []
    for i, line in enumerate(lines):
        if line.rstrip() != '{':
            continue
        # Walk backwards over blank lines to find the previous non-blank line.
        k = i - 1
        while k >= 0 and not lines[k].strip():
            k -= 1
        if k >= 0 and lines[k].rstrip().endswith(')'):
            results.append(i)
    return results


def process_function(lines, body_idx):
    decls_start = skip_leading_comment(lines, body_idx + 1)
    decls, end_idx = parse_decl_block(lines, decls_start)
    if len(decls) <= 1:
        return None

    names = [extract_declared_name(d['first_line']) for d in decls]
    name_to_idx = {n: i for i, n in enumerate(names) if n}

    to_extract = detect_extractions(decls, name_to_idx)

    deps = compute_deps(decls, name_to_idx, skip_extracted=to_extract)

    order = topo_rct_sort(decls, deps, to_extract)

    # Build new section
    new_decl_lines = []
    assignments = []
    # Assignments must be in dep-respecting order. Build by iterating over
    # the original decls (preserves original order which is dep-correct),
    # picking out extracted ones.
    for i, d in enumerate(decls):
        if i in to_extract:
            asg = build_assignment(d['first_line'])
            if asg:
                assignments.append(asg)

    for idx in order:
        if idx in to_extract:
            new_decl_lines.append(strip_initializer(decls[idx]['first_line']))
        else:
            new_decl_lines.extend(decls[idx]['all_lines'])

    # Determine if any change at all
    original_section = lines[decls_start:end_idx]
    if not assignments:
        if new_decl_lines == original_section:
            return None
        return (decls_start, end_idx, new_decl_lines)

    # Add blank line between decls and assignments
    new_section = list(new_decl_lines)
    new_section.append('\n')
    new_section.extend(assignments)

    # Replace lines[decls_start:end_idx]. end_idx is typically the blank line
    # already present; we want to absorb it so we don't end up with two blanks.
    replace_end = end_idx
    if end_idx < len(lines) and not lines[end_idx].strip():
        # Eat the existing blank line; our new_section already provides one
        replace_end = end_idx + 1

    return (decls_start, replace_end, new_section)


def process_file(path, dry_run=False):
    with open(path) as f:
        lines = f.readlines()
    new_lines = list(lines)

    body_starts = find_body_starts(new_lines)
    changes = 0
    for body_idx in reversed(body_starts):
        r = process_function(new_lines, body_idx)
        if r is None:
            continue
        start, end, replacement = r
        new_lines[start:end] = replacement
        changes += 1

    if new_lines != lines and not dry_run:
        with open(path, 'w') as f:
            f.writelines(new_lines)
    return changes


if __name__ == '__main__':
    args = sys.argv[1:]
    dry = False
    if '--dry-run' in args:
        dry = True
        args = [a for a in args if a != '--dry-run']
    total = 0
    for p in args:
        c = process_file(p, dry_run=dry)
        print(f"{'(dry) ' if dry else ''}{p}: {c} block(s) reordered")
        total += c
    print(f"Total blocks reordered: {total}")
